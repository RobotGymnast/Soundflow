{-# LANGUAGE NoImplicitPrelude
           #-}
module Types( Chord
            , Track
            ) where

import Prelewd

import Sound.MIDI.Monad

-- | A group of simultaneous on/off signals
type Chord = [(Maybe Velocity, Note)]
-- | Unique identifier for a record/playback track
type Track = Integer
