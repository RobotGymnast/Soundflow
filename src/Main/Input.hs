{-# LANGUAGE NoImplicitPrelude
           , TupleSections
           , FlexibleContexts
           , TemplateHaskell
           #-}
module Main.Input( inputs
                 ) where

import Summit.Control.Stream
import Summit.Data.Id
import Summit.Data.Map
import Summit.Impure
import Summit.Prelewd

import Control.Stream.Util
import Data.Trie
import Summit.Template.MemberTransformer

import Wrappers.Events

import Sound.MIDI.Monad

import Main.Graphics

import Config
import Input

sequence2 :: (Mappable (->) f a (Either a b), Mappable (->) f b (Either a b))
          => Either (f a) (f b) -> f (Either a b)
sequence2 = either (map Left) (map Right)

mswitch :: Functor m2 => (m1 (a, Stream m1 r a) -> m2 (b, Stream m1 r a)) -> Stream m1 r a -> Stream m2 r b
mswitch f s = Stream $ \r -> mswitch f <$$> f (s $< r)

data Context = Context
            { allMap        :: InputMap                 -- ^ The total mapping of events to inputs
            , currentMap    :: InputMap                 -- ^ The current mapping of events to inputs
            , offMap        :: Map UnifiedEvent Input   -- ^ The current mapping of toggle-off events to inputs
            }

$(memberTransformers ''Context)

inputs :: Stream MIDI () [(Maybe Velocity, Input)]
inputs = (Left <$$> buttons) <&> (<>) <*> (Right <$$> notes) >>> identify convertAll

buttons :: Stream MIDI () [(Bool, Button)]
buttons = mswitch (ioMIDI . \i _-> i)
        $ events
      >>> lift (arr $ traverse toButton)
      >>> identify (arr concat)
    where
        toButton CloseEvent = empty
        toButton (ResizeEvent s) = resize s $> []
        toButton (ButtonEvent b s) = return [(s == Press, b)]
        toButton _ = return []

notes :: Stream MIDI () [(Maybe Velocity, Note)]
notes = lift $ arr $ \_-> midiIn

convertAll :: Stream Id [Either (Bool, Button) (Maybe Velocity, Note)] [(Maybe Velocity, Input)]
convertAll = map (boolToVelocity <&> sequence2 >>> convert) <&> mapMaybe id
    where
        boolToVelocity = arr $ map2 $ map2 (`mcond` defaultVelocity)

convert :: Stream Id (Maybe Velocity, UnifiedEvent) (Maybe (Maybe Velocity, Input))
convert = loop (barr convertFunc) (Context mapInput mapInput mempty) >>> bind hold
    where
        convertFunc (Nothing, e) cxt = (do
                                        (i, off) <- remove e $ offMap cxt
                                        return ( Just (Nothing, i)
                                               , cxt { offMap = off }
                                               )
                                       ) <?> (Nothing, cxt)
        convertFunc (Just v, e) cxt = case trie e $ currentMap cxt of
                                        Nothing -> (Nothing, reset cxt)
                                        Just (Value i) -> case fromRemap i of
                                                Just r -> (Nothing, reset $ allMap' (r <>) cxt)
                                                _ -> ( Just (Just v, i)
                                                     , offMap' (insertWith (error "double-pressed button") e i)
                                                     $ reset
                                                     $ cxt
                                                     )
                                        Just c -> (Nothing, cxt { currentMap = c })

        reset = currentMap' =<< \cxt _-> allMap cxt
