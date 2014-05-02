{-# LANGUAGE TupleSections #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE FlexibleContexts #-}
module Logic ( logic
             ) where

import Prelude ()
import BasicPrelude as Base

import Control.Eff
import Control.Eff.Lift as Eff
import Control.Concurrent.Mutex
import Control.Concurrent.STM
import Control.Lens (view, set, over, (<&>))
import Control.Monad.Trans.Class as Trans
import Data.Conduit
import Data.Conduit.List as Conduit
import Data.HashMap.Strict as HashMap
import Data.Refcount
import Data.Text (unpack)
import Data.Traversable
import Data.Typeable
import Data.Vector as Vector
import Sound.MIDI

import Input
import TrackMemory

trackFile :: Track -> FilePath
trackFile t = fromString $ "track" <> unpack (show t)

hold :: (Monad m, Hashable a, Eq a) => Conduit (a, Maybe b) m (a, Maybe b)
hold = inner mempty
  where
    inner held = do
      mi <- await
      case mi of
        Nothing -> return ()
        Just e -> case e of
          (note, Nothing) -> case removeRef note held of
            Nothing -> inner held
            Just (removed, held') -> do
                if removed
                then yield e
                else return ()
                inner held'
          (note, Just _) -> yield e
                         >> inner (insertRef note held)

liftSTMConduit :: (Typeable1 m, MonadIO m, SetMember Lift (Lift m) r) => STM a -> ConduitM i o (Eff r) a
liftSTMConduit = Trans.lift . liftIO . atomically

logic :: SetMember Lift (Lift IO) env => Conduit Input (Eff env) (Note, Maybe Velocity)
logic = do
    tracks <- newWithLock mempty
    harmonies <- liftSTMConduit $ newTVar mempty
    awaitForever (stepLogic tracks harmonies) =$= hold

initialTrackMemory :: TrackMemory
initialTrackMemory
    = TrackMemory
        { _trackData = Vector.empty
        , _recording = False
        , _playState = Nothing
        }

modifyLockedExtant ::
    MonadIO m =>
    Locked MemoryBank ->
    Track ->
    (TrackMemory -> TrackMemory) ->
    m ()
modifyLockedExtant tracks t f
    = modifyLocked tracks
    $ \memory -> let memory' = if not $ HashMap.member t memory
                               then HashMap.insert t initialTrackMemory memory
                               else memory
                 in over (track t) f memory'

sideEffect :: Functor f => (a -> f ()) -> a -> f a
sideEffect f a = a <$ f a

-- TODO: when harmonies are released, release associated notes properly.
stepLogic ::
    SetMember Lift (Lift IO) env =>
    Locked MemoryBank ->
    TVar (Refcount Harmony) ->
    Input ->
    Conduit i (Eff env) (Note, Maybe Velocity)
stepLogic tracks harmoniesVar
      = \e -> justProcessInput e
          -- Append all the notes that are produced to all the recording tracks.
          =$= Conduit.mapM (sideEffect $ \notes -> onRecordingTracks (`snoc` Right notes))
           >> onRecordingTracks (snocIfTimestep e)
  where
    -- just handle the immediate "consequences" of the input,
    -- with no real attention paid to "long-term" effects.
    justProcessInput e = case e of
        NoteInput note mv -> do
          yield (note, mv)
          harmonies <- liftSTMConduit $ readTVar harmoniesVar
          Base.forM_ (keys $ unRefcount harmonies) $ \h -> do
            yield $ harmonize h (note, mv)

        HarmonyInput harmony isOn -> liftSTMConduit $ do
          modifyTVar' harmoniesVar $ \harmonies ->
              if isOn
              then insertRef harmony harmonies
              else fromMaybe harmonies $ deleteRef harmony harmonies
        
        Track Record t -> do
          modifyLockedExtant tracks t toggleRecording

        Track Play t -> do
          modifyLockedExtant tracks t togglePlaying

        Track Save t -> do
          dat <- readLocked tracks <&> view (track t) <&> view trackData
          Trans.lift $ liftIO $ writeFile (trackFile t) $ show dat

        Track Load t -> do
          dat <- read <$> Trans.lift (liftIO $ readFile (trackFile t))
          modifyLocked tracks $ over (track t) $ set trackData dat

        Timestep dt -> do
          outs <- modifyLockedWithM tracks $ \mem -> do
            (outs, mem') <- Trans.lift
                          $ traverse (advancePlayBy dt) mem
                        <&> HashMap.toList
                        <&> fmap (\(t, (o, d)) -> (o, (t, d)))
                        <&> Base.unzip
            return (outs, HashMap.fromList mem')
          yield (Base.concat outs) =$= Conduit.concat

    onRecordingTracks f
      = modifyLocked tracks $ fmap $ \t ->
          if view recording t
          then over trackData f t
          else t

    snocIfTimestep (Timestep dt) t = snoc t (Left dt)
    snocIfTimestep _ t = t

    toggleRecording t = let recordState = not $ view recording t
                        in (if recordState then set trackData Vector.empty else id) $ over recording not t
    togglePlaying = over playState $ maybe (Just (0, 0)) (\_-> Nothing)

    advancePlayBy dt t
        = case view playState t of
            Nothing -> return ([], t)
            Just (start, remaining) -> let
                  (playState', outs) = continueTo (dt + remaining) start (view trackData t) []
                in return (Base.reverse outs, set playState playState' t)

    continueTo t start v outs
        = if start < Vector.length v
          then case v Vector.! start of
                Left dt ->
                  if dt < t
                  then continueTo (t - dt) (start + 1) v outs
                  else (Just (start, t), outs)
                Right out -> continueTo t (start + 1) v (out : outs)
          else (Nothing, outs)
