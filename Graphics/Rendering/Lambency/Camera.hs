module Graphics.Rendering.Lambency.Camera (
  CameraLocation(..),
  CameraViewDistance(..),
  Camera(..),
  GameCamera(..),
  mkOrthoCamera,
  getViewProjMatrix,

  getCamLoc,
  setCamLoc,
  getCamDist,
  setCamDist,
  getCamPos,
  setCamPos,
  getCamDir,
  setCamDir,
  getCamUp,
  setCamUp,
  getCamNear,
  setCamNear,
  getCamFar,
  setCamFar
) where
--------------------------------------------------------------------------------
import Graphics.Rendering.Lambency.Utils

import Data.Vect.Float
--------------------------------------------------------------------------------

data CameraLocation = CameraLocation {
  camPos :: Vec3,
  camDir :: Normal3,
  camUp :: Normal3
} deriving (Show)

data CameraViewDistance = CameraViewDistance {
  near :: Float,
  far :: Float
} deriving (Show)

data CameraType =
  Ortho {
    left :: Float,
    right :: Float,
    top :: Float,
    bottom :: Float
    }
--  | Persp {
--    fovY :: Float,
--    aspect :: Float
--    }

data Camera = Camera CameraLocation CameraType CameraViewDistance

type Time = Double
data GameCamera = GameCamera Camera (Time -> Camera -> Camera)

mkOrthoCamera :: Vec3 -> Normal3 -> Normal3 ->
                 Float -> Float -> Float -> Float -> Float -> Float ->
                 Camera
mkOrthoCamera pos dir up l r t b n f = Camera
  CameraLocation {
     camPos = pos,
     camDir = dir,
     camUp = up
  }

  Ortho {
    left = l,
    right = r,
    top = t,
    bottom = b
  }

  CameraViewDistance {
    near = n,
    far = f
  }

getCamLoc :: Camera -> CameraLocation
getCamLoc (Camera loc _ _) = loc

setCamLoc :: Camera -> CameraLocation -> Camera
setCamLoc (Camera _ cam dist) loc = Camera loc cam dist

getCamDist :: Camera -> CameraViewDistance
getCamDist (Camera _ _ dist) = dist

setCamDist :: Camera -> CameraViewDistance -> Camera
setCamDist (Camera loc cam _) dist = Camera loc cam dist

getCamPos :: Camera -> Vec3
getCamPos = (camPos . getCamLoc)

setCamPos :: Camera -> Vec3 -> Camera
setCamPos c p = let
  loc = getCamLoc c
  in
   setCamLoc c $ (\l -> l { camPos = p }) loc

getCamDir :: Camera -> Normal3
getCamDir = (camDir . getCamLoc)

setCamDir :: Camera -> Normal3 -> Camera
setCamDir c d = let
  loc = getCamLoc c
  in
   setCamLoc c $ (\l -> l { camDir = d }) loc

getCamUp :: Camera -> Normal3
getCamUp = (camUp . getCamLoc)

setCamUp :: Camera -> Normal3 -> Camera
setCamUp c u = let
  loc = getCamLoc c
  in
   setCamLoc c $ (\l -> l { camUp = u }) loc

getCamNear :: Camera -> Float
getCamNear = (near . getCamDist)

setCamNear :: Camera -> Float -> Camera
setCamNear c n = let
  dist = getCamDist c
  in
   setCamDist c $ (\d -> d { near = n }) dist

getCamFar :: Camera -> Float
getCamFar = (far . getCamDist)

setCamFar :: Camera -> Float -> Camera
setCamFar c f = let
  dist = getCamDist c
  in
   setCamDist c $ (\d -> d { far = f }) dist

getViewMatrix :: Camera -> Mat4
getViewMatrix c = let
  dir = getCamDir c
  side = crossprod dir $ getCamUp c
  up = side &^ dir
  te :: Normal3 -> Float
  te n = neg (getCamPos c) &. (fn n)
  in
   if compareZero side then
     one
   else
     -- rotation part
     Mat4 (en side) (en up) (neg $ en dir) $
     -- translation part
     Vec4 (te side) (te up) (- te dir) 1.0
  where
    ez :: Vec3 -> Vec4
    ez = extendZero
    fn :: Normal3 -> Vec3
    fn = fromNormal
    en = ez . fn

getProjMatrix :: Camera -> Mat4
getProjMatrix (Camera _ (Ortho {top = t, bottom = b, left = l, right = r}) dist) = let
  n = near dist
  f = far dist
  in
   Mat4
   (Vec4 (2.0 / (r - l)) 0 0 0)
   (Vec4 0 (2.0 / (t - b)) 0 0)
   (Vec4 0 0 ((-2.0) / (f - n)) 0)
   (Vec4 (-(r+l)/(r-l)) (-(t+b)/(t-b)) (-(f+n)/(f-n)) 1)

getViewProjMatrix :: Camera -> Mat4
getViewProjMatrix c = (getViewMatrix c) .*. (getProjMatrix c)
