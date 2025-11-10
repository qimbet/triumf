#!/bin/bash

cd ~/triumfFiles/epics/epics_installer18.04/packages/tarFiles || exit

for file in *.tar.*; do
    echo "Extracting $file..."
    case "$file" in
        *.tar.gz|*.tgz)    tar -xzf "$file" ;;
        *.tar.bz2|*.tbz2)  tar -xjf "$file" ;;
        *) echo "Unknown file type: $file" ;;
    esac
done

