#!/bin/bash

# Define the default Steam library path
DEFAULT_STEAMAPPS_PATH="${HOME}/.local/share/Steam/steamapps"

# Define an array of Steam library steamapps paths to search
# Add your additional library paths to this array
STEAMAPPS_PATHS=(
    "${DEFAULT_STEAMAPPS_PATH}"
    "/run/media/mmcblk0p1/steamapps"
    "/run/media/data/SteamLibrary/steamapps"
    # <-- Add other custom path here
)

# Check if at least one of the defined Steam paths exists
found_steam_path=false
for steam_path in "${STEAMAPPS_PATHS[@]}"; do
    if [ -d "${steam_path}" ]; then
        found_steam_path=true
        break
    fi
done

if [ "$found_steam_path" = false ]; then
    echo "No Steam library paths found. Please check the STEAMAPPS_PATHS array in the script."
    exit 1
fi

# Build the find command arguments dynamically from the array
FIND_PATHS=""
for steam_path in "${STEAMAPPS_PATHS[@]}"; do
    if [ -d "${steam_path}" ]; then
        FIND_PATHS+=" \"${steam_path}\""
    fi
done

# Function to process and print game info
process_game_info() {
    local file="$1"
    local game_pattern="$2"
    local steam_paths_ref=("${@:3}") # Capture array of paths

    local appid
    appid=$(basename "$file" | sed 's/appmanifest_\(.*\)\.acf/\1/')
    local game_name
    game_name=$(grep -Po '"name"\s+"\K[^"]+' "$file")

    # Skip if no game name found
    if [ -z "$game_name" ]; then return; fi

    # Filter by pattern if provided
    if [ -n "$game_pattern" ]; then
        if [[ ! "$game_name" =~ ${game_pattern} ]]; then return; fi
    fi

    # --- Logic to find the compatdata folder ---
    local manifest_dir
    manifest_dir=$(dirname "$file")
    
    # 1. Assume standard behavior: compatdata is in the same library as the game
    local expected_path="${manifest_dir}/compatdata/${appid}"
    local final_path="$expected_path"
    local status_suffix=""
    local found=false

    if [ -d "$expected_path" ]; then
        found=true
        final_path="$expected_path"
    else
        # 2. If not local, search ALL known library paths for this ID
        # (This catches cases where the prefix is on internal drive but game is on SD card)
        for lib_path in "${STEAMAPPS_PATHS[@]}"; do
            local possible_path="${lib_path}/compatdata/${appid}"
            if [ -d "$possible_path" ]; then
                found=true
                final_path="$possible_path"
                break
            fi
        done
    fi

    # --- Determine Status Tags ---
    if [ "$found" = false ]; then
        status_suffix=" [MISSING]"
        # We keep $final_path as the $expected_path so the user knows where it SHOULD be
    else
        # Check if directory is empty
        if [ -z "$(ls -A "$final_path")" ]; then
            status_suffix=" [EMPTY]"
        fi
    fi

    echo "$final_path -> $game_name$status_suffix"
}

# Export function and variables for use in subshells if necessary, 
# though standard pipes usually inherit variables. 
# We pass the logic inline below to avoid scope issues.

# Determine pattern argument
PATTERN=""
if [ $# -ne 0 ]; then
    PATTERN="$*"
fi

# Run the find command and process
eval "find ${FIND_PATHS} -maxdepth 1 -name 'appmanifest_*.acf' -print0" | while IFS= read -r -d '' file; do
    process_game_info "$file" "$PATTERN"
done | sort -V
