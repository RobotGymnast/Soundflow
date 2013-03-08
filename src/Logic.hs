{-# LANGUAGE NoImplicitPrelude
           , TupleSections
           , MultiParamTypeClasses
           , FlexibleInstances
           , FunctionalDependencies
           , UndecidableInstances
           #-}
module Logic ( Song
             , song
             ) where

import Prelewd

import Impure

import Control.Stream
import Data.Tuple
import Sound.MIDI.Monad
import Storage.Id
import Storage.Map
import Subset.Num

import Input

type Song = [(Bool, (Tick, Note))]

class Propogate r a b where
    propogate :: r -> a -> b

instance Propogate r a (r, a) where
    propogate = (,)

instance (Propogate r a b, Propogate r x y) => Propogate r (a, x) (b, y) where
    propogate r = propogate r *** propogate r

song :: Stream Id ((Bool, Input), Tick) Song
song = updater (memory &&& noteLogic >>> loop (barr toSong) mempty) []
    where
        memory = arr (fst.fst) &&& record >>> playback
        noteLogic = arr (fst.fst) >>> arr (map fromMelody) &&& harmonies

record :: Stream Id (((Bool, Input), Tick), Song) Song
record = updater (map2 (map2 $ map2 $ barr recordPressed) >>> barr state) (Nothing, []) >>> arr snd
    where
        recordPressed pressed inpt = pressed && isRecord inpt

        state ((pressed, dt), notes) (Just t, sng) = let t' = mcond (not pressed) $ dt + t
                                                     in (t', (map (map2 (t +)) <$> notes) <> sng)
        state ((pressed, _), _) (Nothing, sng) = iff pressed (Just 0, []) (Nothing, sng)

playback :: Stream Id ((Bool, Input), Song) Song
playback = barr $ \(b, i) s -> guard (b && isPlay i) >> s

try' :: (a -> Maybe a) -> a -> a
try' f x = f x <?> x

harmonies :: Stream Id (Bool, Input) [Harmony]
harmonies = arr (map fromHarmony) >>> updater (barr newInputMap) initHarmonies >>> arr keys
    where
        initHarmonies = singleton 0 (1 :: Positive Integer)

        newInputMap (_, Nothing) m = m
        newInputMap (True, Just shifts) m = foldr (\s -> insertWith (+) s 1) m shifts
        newInputMap (False, Just shifts) m = foldr (\s -> try' $ modify (\v -> toPos $ fromPos v - 1) s) m shifts

toSong :: (Song, ((Bool, Maybe [Note]), [Harmony]))
       -> Map (Pitch, Instrument) [Harmony]
       -> (Song, Map (Pitch, Instrument) [Harmony])
toSong (sng, ((_, Nothing), _)) hmap = (sng, hmap)
toSong (sng, ((True, Just notes), hs)) hmap = ( ((True,) . (0,) <$> (harmonize <$> notes <*> hs)) <> sng
                                              , foldr (\n -> insert (pitch n, instr n) hs) hmap notes
                                              )
toSong (sng, ((False, Just notes), _)) hmap = foldr newHarmonies (sng, hmap) notes
    where
        newHarmonies note (s, m) = let (v, m') = remove (pitch note, instr note) m <?> error "double-removal"
                                   in (((False,) . (0,) . harmonize note <$> v) <> s, m')

harmonize :: Note -> Harmony -> Note
harmonize note dp = pitch' (\p -> fromIntegral $ fromIntegral p + dp) note
