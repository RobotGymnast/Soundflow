{-# LANGUAGE NoImplicitPrelude
           #-}
module Input ( Input (..)
             , ButtonMap
             , MIDIMap
             , InputMap
             , fromMelody
             , fromHarmony
             , isRecord
             , isPlay
             , fromRemap
             ) where

import Prelewd

import Data.Int
import Sound.MIDI.Monad.Types
import Storage.Map

import Wrappers.Events

type ButtonMap = Map Button Input
type MIDIMap = Map (Pitch, Instrument) (Velocity -> Input)
type InputMap = (ButtonMap, MIDIMap)

data Input = Melody [Note]
           | Harmony [Int16]
           | Record
           | Play
           | Remap InputMap

fromMelody :: Input -> Maybe [Note]
fromMelody (Melody s) = Just s
fromMelody _ = Nothing

fromHarmony :: Input -> Maybe [Int16]
fromHarmony (Harmony hs) = Just hs
fromHarmony _ = Nothing

isRecord :: Input -> Bool
isRecord Record = True
isRecord _ = False

isPlay :: Input -> Bool
isPlay Play = True
isPlay _ = False

fromRemap :: Input -> Maybe InputMap
fromRemap (Remap r) = Just r
fromRemap _ = Nothing
