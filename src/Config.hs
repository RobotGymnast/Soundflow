{-# LANGUAGE NoImplicitPrelude
           , TupleSections
           #-}
-- | Settings are stored in this module
module Config ( windowSize
              , displayOpts
              , title
              , inMIDI
              , outMIDI
              , drumChannel
              , bpm
              , granularity
              , defaultVelocity
              , mapInput
              ) where

import Summit.Prelewd

import Data.Char
import Data.Tuple
import Summit.Data.Map
import Data.Trie

import Sound.MIDI.Monad.Types

import Wrappers.Events
import Wrappers.GLFW (DisplayOptions (..), defaultDisplayOptions)

import Input

windowSize :: Num a => (a, a)
windowSize = (64, 64)

-- | GLFW display options
displayOpts :: DisplayOptions
displayOpts = defaultDisplayOptions
    { displayOptions_width = fst windowSize
    , displayOptions_height = snd windowSize
    , displayOptions_windowIsResizable = True
    }

-- | Title of the game window
title :: Text
title = "Soundflow"

-- | Output MIDI destinations
outMIDI :: [Text]
outMIDI = ["128:0"]

-- | Map MIDI sources to instruments
inMIDI :: Map Text Instrument
inMIDI = fromList []

drumChannel :: Num a => a
drumChannel = 9

-- | Beats per minute
bpm :: Integer
bpm = 60

granularity :: Tick
granularity = 2

numChar :: Integer -> Char
numChar i = "0123456789" ! i

defaultVelocity :: Velocity
defaultVelocity = 64

-- | What controls what?
mapInput :: InputMap
mapInput = fromMap (map Left <.> fromList (harmonyButtons <> recordButtons))
        <> pianoMap
        <> drumMIDI
    where
        harmonyButtons = map ((:[]) . KeyButton . CharKey *** Harmony)
                       $ [(numChar i, [(Nothing, (Nothing, Right $ fromInteger i))]) | i <- [1..9]]
                      <> [('[', [(Just 32, (Just Percussion, Left 42))])]

        recordButtons = map (map2 $ map (KeyButton . CharKey))
                      $ do i <- [1..9]
                           let c = numChar i
                           [(['Z', c], Record i), (['X', c], Play i)]

piano :: Pitch -> Note
piano = (, Instrument 0)

pianoMIDI :: InputMap
pianoMIDI = fromMap $ fromList $ ((:[]) . Right *** Chord) <$> [(piano n, [piano n]) | n <- [0..120]]

drumMIDI :: InputMap
drumMIDI = fromMap $ fromList $ ((:[]) . Right *** Chord) <$> [(drum n, [drum n]) | n <- [35..81]]
    where drum = (, Percussion)

pianoMap :: InputMap
pianoMap = fromMap (fromList $ noteButtons <> harmonyButtons <> remapButtons) <> pianoMIDI
    where
        noteButtons = map ((:[]) . Left . KeyButton . CharKey *** Chord . map piano)
            [("ASDFGHJK" ! i, [[48, 50, 52, 53, 55, 57, 59, 60] ! i]) | i <- [0..7]]

        harmonyButtons = map ((:[]) . Left . KeyButton . CharKey *** Harmony)
            [("QWERTYUIOP" ! i, [(Just (-16), (Just $ Instrument 40, Right $ fromInteger i))]) | i <- [0..9]]

        remapButtons = map ((:[]) . Left . KeyButton . CharKey *** Remap)
            [ (';', violinMap)
            ]

violinMap :: InputMap
violinMap = fromMap
          $ (map Left <.> fromList (noteButtons <> harmonyButtons <> remapButtons))
         <> (map Right <.> fromList violinMIDI)
    where
        violin = (, Instrument 40)

        noteButtons = map ((:[]) . KeyButton . CharKey *** Chord . map violin)
            [("ASDFGHJK" ! i, [[48, 50, 52, 53, 55, 57, 59, 60] ! i]) | i <- [0..7]]

        harmonyButtons = map ((:[]) . KeyButton . CharKey *** Harmony)
            [("QWERTYUIOP" ! i, [(Just 8, (Just $ Instrument 0, Right $ fromInteger i))]) | i <- [0..9]]

        remapButtons = map ((:[]) . KeyButton . CharKey *** Remap)
            [ (';', pianoMap)
            ]

        violinMIDI = map ((:[]) *** Chord)
            [((36 + i, Instrument 0), [(48 + i, Instrument 40)]) | i <- [0..23]]
