**wam** is a command-line utility to bulk install and update [World of Warcraft](https://battle.net/wow) addons. It uses [Curse.com](http://mods.curse.com/addons/wow) addons database.

# Installation

**wam** requires NodeJS and NPM. Having both set up you can just install it as a global package:

`npm install -g wam`

# Configuration

**wam** reads a `wamfile` config file to know where is located your World of Warcraft installation and which addons you want to install/update.

A `wamfile` is just a JSON file with two keys:

1. `wowPath` has a string associated telling **wam** where is located your World of Warcraft installation. The path should point to the folder containing World of Warcraft executable and `Interface` folder.
1. `addons` is an array of strings. Each item is a `Curse identifier` of an addon.

## Curse identifiers

The easiest way to know the identifier of an addon is searching it in [Curse.com database](http://mods.curse.com/addons/wow). Each addon has an information page with a download link and the URL to that page follows this pattern: `http://mods.curse.com/addons/wow/<curse-identifier>`.

For instance, [Deadly Boss Mods](http://mods.curse.com/addons/wow/deadly-boss-mods)'s identifier is `deadly-boss-mods`.

# Usage

`[INFO] Usage: wam <command> [wamfilePath]`

**wam** supports two commands:

1. `init` will create a sample `wamfile` in specified folder.
2. `update` installs or updates addons specified by `wamfile` at given path.

If no path is given the current directory will be used.

# To do...

[ ] Add some images to Readme.