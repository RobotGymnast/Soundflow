{-# LANGUAGE TupleSections #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE CPP #-}
module Logic ( logic
             ) where

import Prelude ()
import BasicPrelude as Base

import Control.Eff (Eff, SetMember)
import Control.Eff.Lift as Eff
import Control.Concurrent.STM
import Control.Lens
import Control.Monad.Trans.Class as Trans
import Data.Conduit
import Data.Conduit.List as Conduit
import Data.HashMap.Strict as HashMap
import Data.OpenUnion
import Data.Refcount
import Data.Text (unpack)
import Sound.MIDI

import Data.Conduit.Extra
import Input
import TrackMemory

#if MIN_VERSION_base(4,7,0)
#else
#define Typeable Typeable1
#endif

-- TODO: Can this be generalized? e.g. to `Lens s t a b`.
-- | `overT` is to `traverse` as `over` is to `fmap`.
overT :: Functor f => Lens' s a -> (a -> f a) -> s -> f s
overT l f s = f (view l s) <&> \a -> set l a s

trackFile :: TrackNumber -> FilePath
trackFile t = fromString $ unpack $ "track" <> show t

-- | "Hold" inputs by counting the number of @Just@ and @Nothing@ (on and off)
-- signals for a given @a@, and only send the off signal corresponding to the
-- last on signal.
hold :: (MonadIO m, Hashable a, Eq a) => Conduit (a, Maybe b) m (a, Maybe b)
hold = inner mempty
  where
    inner held = do
      awaitOr () $ \case
        e@(note, Nothing) -> case removeRef note held of
            Nothing -> do
                putStrLn $ "off signal without corresponding on signal"
                inner held
            Just (removed, held') -> do
                if removed
                then yield e
                else return ()
                inner held'
        e@(note, Just _) -> do
            yield e
            inner (insertRef note held)

liftSTMConduit :: (Typeable m, MonadIO m, SetMember Lift (Lift m) r) => STM a -> ConduitM i o (Eff r) a
liftSTMConduit = Trans.lift . liftIO . atomically

logic :: SetMember Lift (Lift IO) env => Conduit Input (Eff env) (Note, Maybe Velocity)
logic = do
    tracks <- liftSTMConduit $ newTVar mempty
    harmonies <- liftSTMConduit $ newTVar mempty
    awaitForever (stepLogic tracks harmonies) =$= hold

sideEffect :: Functor f => (a -> f ()) -> a -> f a
sideEffect f a = a <$ f a

observeTVar :: TVar a -> (a -> (b, a)) -> STM b
observeTVar t f = do
    a <- readTVar t
    let (b, a') = f a
    writeTVar t a'
    return b

toRests :: Input -> [TrackOutput]
toRests (Timestep dt) = [RestOutput dt]
toRests _ = []

-- TODO: when harmonies are released, release associated notes properly.
stepLogic ::
    SetMember Lift (Lift IO) env =>
    TVar TrackMemory ->
    TVar (Refcount Harmony) ->
    Input ->
    Conduit i (Eff env) (Note, Maybe Velocity)
stepLogic tracks harmoniesVar
      = \i -> do
          justProcessInput i
              =$= Conduit.concat
              -- Append all the notes that are produced to all the recording tracks.
              =$= Conduit.mapM (sideEffect $ \(note, v) -> tracksIO modifyTVar $ record [NoteOutput note v])
          Trans.lift $ tracksIO modifyTVar $ record $ toRests i
  where
    tracksIO ::
      MonadIO m =>
      (TVar TrackMemory -> a -> STM b) ->
      a ->
      m b
    tracksIO f = liftIO . atomically . f tracks

    -- just handle the immediate "consequences" of the input,
    -- with no real attention paid to "long-term" effects.
    justProcessInput = \case
        NoteInput note mv -> do
          yield [(note, mv)]
          harmonies <- liftSTMConduit $ readTVar harmoniesVar
          yield $ [harmonize h (note, mv) | h <- keys $ unRefcount harmonies]

        HarmonyInput harmony isOn -> liftSTMConduit $ do
          modifyTVar' harmoniesVar $ \harmonies ->
            if isOn
            then insertRef harmony harmonies
            else fromMaybe harmonies $ deleteRef harmony harmonies
        
        Track Record t -> do
          outputs <- tracksIO observeTVar $
            overT (track t)
              $ ([],) . stopRecording
              @> startRecording
          yield outputs

        Track (Play l) t -> do
          outputs <- tracksIO observeTVar $
            overT (track t)
              $  stopPlaying
              @> ([],) . startPlaying l
          yield outputs

        Track Save t -> do
          dat <- liftIO $ atomically $ readTVar tracks <&> view (track t) <&> view trackData
          Trans.lift $ liftIO $ writeFile (trackFile t) $ show dat

        Track Load t -> do
          dat <- read <$> Trans.lift (liftIO $ readFile $ trackFile t)
          tracksIO modifyTVar $ over (track t) (set trackData dat)

        Timestep dt -> do
          outputs <- tracksIO observeTVar $ playSome dt
          yield outputs
