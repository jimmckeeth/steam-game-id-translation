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

# Function to process and collect game info
process_game_info() {
    local file="$1"
    local game_pattern="$2"

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
    
    local expected_path="${manifest_dir}/compatdata/${appid}"
    local final_path="$expected_path"
    local found=false

    if [ -d "$expected_path" ]; then
        found=true
        final_path="$expected_path"
    else
        for lib_path in "${STEAMAPPS_PATHS[@]}"; do
            local possible_path="${lib_path}/compatdata/${appid}"
            if [ -d "$possible_path" ]; then
                found=true
                final_path="$possible_path"
                break
            fi
        done
    fi

    # --- Determine Status ---
    local status_code=1 # Default: Populated
    if [ "$found" = false ]; then
        status_code=3 # No folder
    else
        if [ -z "$(ls -A "$final_path")" ]; then
            status_code=2 # Empty
        fi
    fi

    # Output a parsable line for sorting
    # Format: StatusCode<TAB>GameName<TAB>FullPath<TAB>AppManifestFile
    echo -e "${status_code}\t${game_name}\t${final_path}\t${file}"
}

# Determine pattern argument
PATTERN=""
if [ $# -ne 0 ]; then
    PATTERN="$*"
fi

# Collect all game data first in a format suitable for sorting.
all_games_data=$(eval "find ${FIND_PATHS} -maxdepth 1 -name 'appmanifest_*.acf' -print0" | while IFS= read -r -d '' file; do
    process_game_info "$file" "$PATTERN"
done)

# Sort the collected data.
# Sort by: 1. Status code (numeric), 2. Game Name (alphabetic).
sorted_games_data=$(echo "${all_games_data}" | sort -t$'\t' -k1,1n -k2,2)

# --- Calculate max path length for alignment ---
max_path_len=0
# Use a while loop with a here-string to read the sorted data.
# This avoids a subshell, ensuring max_path_len is available afterwards.
while IFS=$'\t' read -r status_code game_name final_path appmanifest_path; do
    # Skip empty lines
    if [ -z "$game_name" ]; then continue; fi
    
    path_to_check=""
    if [[ "$status_code" -eq 3 ]]; then
        path_to_check="$appmanifest_path"
    else
        path_to_check="$final_path"
    fi

    if (( ${#path_to_check} > max_path_len )); then
        max_path_len=${#path_to_check}
    fi
done <<< "${sorted_games_data}"


# --- Print sorted and formatted data with headers ---
current_status=0
while IFS=$'\t' read -r status_code game_name final_path appmanifest_path; do
    # Skip empty lines
    if [ -z "$game_name" ]; then continue; fi

    # Print header when status changes
    if [[ "$status_code" -ne "$current_status" ]]; then
        # Add a newline before the next header (but not at the very top)
        if [[ "$current_status" -ne 0 ]]; then
            echo
        fi
        current_status=$status_code
        
        if [[ "$status_code" -eq 1 ]]; then
            echo "[Populated folders]"
        elif [[ "$status_code" -eq 2 ]]; then
            echo "[Empty folders]"
        elif [[ "$status_code" -eq 3 ]]; then
            echo "[No folder]"
        fi
    fi

    # Determine which path to print and format the output
    path_to_print=""
    if [[ "$status_code" -eq 3 ]]; then
        path_to_print="$appmanifest_path"
    else
        path_to_print="$final_path"
    fi
    
    printf "%-${max_path_len}s -> %s\n" "$path_to_print" "$game_name"

done <<< "${sorted_games_data}"
