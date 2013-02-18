# Setting Up

To build and run the game, you will need:

 * Haskell
 * cabal
 * llvm
 * Step (https://github.com/RobotGymnast/Step)
 * Game-Wrappers (https://github.com/RobotGymnast/Game-Wrappers)

You can set up the build environment by running

    scripts/setup.sh

Doing so is **mandatory** before committing any code, as this also sets up pre-commit hooks.
All scripts should be run from the project root directory.

# Building

When the environment has been successfully set up, the project can be built with

    scripts/build.sh

# Running

After a successful build, the game can be run from

    dist/build/Growth/Growth

Keys are configurable in `src/Config.hs`

## Mixing

Objects mix with one another as shown in `Game/Object.hs`.
The order in which a tile mixes with its neighbours is up, left, right, down.

## Updating

Updating is done incrementally whenever the update key (configurable) is held.
I don't want to explain all the intricacies of _how_ the objects update.
For that, look at the Object Behaviours at the bottom of Game.Object.

# Documentation

Haddock documentation can be generated using

    scripts/docgen.sh

By default, the documentation is generated to `dist/docs/html/`

# Tests

To run the tests after a successful build, run

    scripts/test.sh

# Code Standards

The `Util` and `Wrappers` folders are for code which is *not project-specific*:
Direct library wraps go into `Wrappers/`, and useful generic functions and modules go in `Util/`.

Coding is a language. You are expressing ideas, so they should be as clear, concise, and elegant as possible.

 * Wrap to 120 characters
 * Functions ending with a single quote usually require a transformation function as one of their parameters
 * When indenting multi-lined bodies, align SOMETHING visually (e.g. operators)
   or just use a multiple of four spaces (at least 8)
 * Indent a `where` keyword by 4 spaces, and the declarations within it by 8
 * If a `where` clause has more than one line in it, the `where` keyword should be on a distinct line from any code
 * Do not have more than one embedded subscope (A `let` inside a `where` is acceptable, but to be used sparingly)
