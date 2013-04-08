{-# LANGUAGE NoImplicitPrelude
           #-}
module Input ( Input (..)
             , UnifiedEvent
             , Song
             , Harmony
             , Track
             , InputMap
             , fromChord
             , fromHarmony
             , fromRecord
             , fromPlay
             , fromRemap
             ) where

import Prelewd

import Data.Int
import Sound.MIDI.Monad.Types
import Storage.Trie

import Wrappers.Events

type UnifiedEvent = Either Button Note
type Song = [(Tick, (Maybe Velocity, Note))]
-- | A Harmony consists of an optional velocity shift,
-- an optional instrument, and a pitch shift.
type Harmony = (Maybe Int16, (Maybe Instrument, Int16))
type Track = Integer
type InputMap = Trie UnifiedEvent Input

data Input = Chord [Note]
           | Harmony [Harmony]
           | Record Track
           | Play Track
           | Remap InputMap

fromChord :: Input -> Maybe [Note]
fromChord (Chord s) = Just s
fromChord _ = Nothing

fromHarmony :: Input -> Maybe [Harmony]
fromHarmony (Harmony hs) = Just hs
fromHarmony _ = Nothing

fromRecord :: Input -> Maybe Track
fromRecord (Record t) = Just t
fromRecord _ = Nothing

fromPlay :: Input -> Maybe Track
fromPlay (Play t) = Just t
fromPlay _ = Nothing

fromRemap :: Input -> Maybe InputMap
fromRemap (Remap r) = Just r
fromRemap _ = Nothing
