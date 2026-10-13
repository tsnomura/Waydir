#!/bin/sh
ico2png --input "$1" --output - | pngview --input -
