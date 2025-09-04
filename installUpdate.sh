#!/bin/bash
set -e
set -u
# THIS IS IN ALPHA USE AT YOUR OWN RISK
# Function to display usage
usage() {
    echo "Usage for creation: $0 --app-name \"App Name\" --cask-token \"cask-token\" --version \"1.0.0\" \\"
    echo "          --arm-url \"https://example.com/app-arm.dmg\" --arm-sha256 \"arm_sha256\" \\"
    echo "          [--intel-url \"https://example.com/app-intel.dmg\" --intel-sha256 \"intel_sha256\"] \\"
    echo "          --homepage \"https://example.com\" --description \"A short description\" \\"
    echo "          --quit-id \"com.example.app\" --tap-owner \"your-github-username\" \\"
    echo "          --tap-repo \"homebrew-your-tap\""
    echo ""
    echo "Usage for update: $0 --tap-owner \"your-github-username\" --tap-repo \"homebrew-your-tap\" --update [--cask-token \"cask-token\"]"
    exit 1
}

# Initialize variables
APP_NAME=""
CASK_TOKEN=""
VERSION=""
ARM_URL=""
ARM_SHA256=""
INTEL_URL=""
INTEL_SHA256=""
HOMEPAGE=""
DESCRIPTION=""
QUIT_ID=""
TAP_OWNER=""
TAP_REPO=""
UPDATE=0

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --app-name) APP_NAME="$2"; shift ;;
        --cask-token) CASK_TOKEN="$2"; shift ;;
        --version) VERSION="$2"; shift ;;
        --arm-url) ARM_URL="$2"; shift ;;
        --arm-sha256) ARM_SHA256="$2"; shift ;;
        --intel-url) INTEL_URL="$2"; shift ;;
        --intel-sha256) INTEL_SHA256="$2"; shift ;;
        --homepage) HOMEPAGE="$2"; shift ;;
        --description) DESCRIPTION="$2"; shift ;;
        --quit-id) QUIT_ID="$2"; shift ;;
        --tap-owner) TAP_OWNER="$2"; shift ;;
        --tap-repo) TAP_REPO="$2"; shift ;;
        --update) UPDATE=1 ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

# Validate required parameters
if [ $UPDATE -eq 0 ]; then
    if [ -z "$APP_NAME" ] || [ -z "$CASK_TOKEN" ] || [ -z "$VERSION" ] || \
       [ -z "$ARM_URL" ] || [ -z "$ARM_SHA256" ] || \
       [ -z "$HOMEPAGE" ] || [ -z "$DESCRIPTION" ] || \
       [ -z "$QUIT_ID" ] || [ -z "$TAP_OWNER" ] || [ -z "$TAP_REPO" ]; then
        echo "Error: Missing required parameters for creation."
        usage
    fi
else
    if [ -z "$TAP_OWNER" ] || [ -z "$TAP_REPO" ]; then
        echo "Error: Missing required parameters for update."
        usage
    fi
fi

# Check if brew is installed
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed. Please install Homebrew first."
    exit 1
fi

# Check if jq is installed (required for GitHub API parsing in update mode)
if [ $UPDATE -eq 1 ] && ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing via Homebrew..."
    brew install jq
fi

echo "--- Starting Homebrew Cask Management ---"

# Determine tap path
BREW_REPOSITORY="$(brew --repository)"
TAP_PATH="${BREW_REPOSITORY}/Library/Taps/${TAP_OWNER}/${TAP_REPO}"
CASK_DIR="${TAP_PATH}/Casks"

echo "Determined tap path: ${TAP_PATH}"

# Homebrew Tap Management
echo "Checking if tap ${TAP_OWNER}/${TAP_REPO} is tapped..."
if ! brew tap | grep -q "${TAP_OWNER}/${TAP_REPO}"; then
    echo "Tap not found. Tapping ${TAP_OWNER}/${TAP_REPO}..."
    brew tap "${TAP_OWNER}/${TAP_REPO}"
else
    echo "Tap ${TAP_OWNER}/${TAP_REPO} is already tapped."
fi

echo "Checking if tap repository exists locally at ${TAP_PATH}..."
if [ ! -d "${TAP_PATH}" ]; then
    echo "Tap repository not found. Attempting to clone it..."
    git clone "https://github.com/${TAP_OWNER}/${TAP_REPO}.git" "${TAP_PATH}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone tap repository. Please ensure it exists and you have access."
        exit 1
    fi
else
    echo "Tap repository already exists locally. Pulling latest changes..."
    cd "${TAP_PATH}"
    git pull origin main
fi

# Update mode
if [ $UPDATE -eq 1 ]; then
    function update_cask() {
        local cask_token="$1"
        local cask_file="${CASK_DIR}/${cask_token}.rb"

        if [ ! -f "$cask_file" ]; then
            echo "Cask file not found for ${cask_token}."
            return
        fi

        # Extract current version
        current_version=$(grep '^  version ' "$cask_file" | sed -E 's/.*"([^"]+)".*/\1/')

        # Get latest tag from GitHub
        latest_tag=$(curl -s "https://api.github.com/repos/${TAP_OWNER}/${cask_token}/releases/latest" | jq -r .tag_name)
        if [ "$latest_tag" = "null" ]; then
            echo "No latest release found for ${cask_token}."
            return
        fi

        # Strip 'v' prefix if present in tag but not in current version
        if [[ "$latest_tag" == v* ]] && [[ "$current_version" != v* ]]; then
            latest_version="${latest_tag#v}"
        else
            latest_version="$latest_tag"
        fi

        # Compare versions
        if [ "$current_version" = "$latest_version" ]; then
            echo "${cask_token} is already at the latest version (${current_version})."
            return
        fi
        if [ "$(printf '%s\n' "$current_version" "$latest_version" | sort -V | head -n1)" != "$current_version" ]; then
            echo "${latest_version} is not newer than ${current_version} for ${cask_token}."
            return
        fi

        # Check if architecture-specific blocks exist
        has_arch=$(grep -q 'on_arm do' "$cask_file"; echo $?)

        # Extract URLs and check for #{version}
        if [ $has_arch -eq 0 ]; then
            arm_url=$(sed -n '/on_arm do/,/end/p' "$cask_file" | grep '^    url ' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! "$arm_url" =~ \#\{version\} ]]; then
                echo "Arm URL does not contain \#{version} for ${cask_token}. Cannot auto-update."
                return
            fi

            intel_url=$(sed -n '/on_intel do/,/end/p' "$cask_file" | grep '^    url ' | sed -E 's/.*"([^"]+)".*/\1/' || true)
            has_intel=0
            if [ -n "$intel_url" ]; then
                if [[ ! "$intel_url" =~ \#\{version\} ]]; then
                    echo "Intel URL does not contain \#{version} for ${cask_token}. Cannot auto-update."
                    return
                fi
                has_intel=1
            fi
        else
            main_url=$(grep '^  url ' "$cask_file" | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! "$main_url" =~ \#\{version\} ]]; then
                echo "URL does not contain \#{version} for ${cask_token}. Cannot auto-update."
                return
            fi
        fi

        # Compute new URLs, download, and calculate new SHAs
        if [ $has_arch -eq 0 ]; then
            new_arm_url="${arm_url/\#{version\}/$latest_version}"
            tmp_arm="/tmp/${cask_token}-arm.dmg"
            if ! curl -f -L -o "$tmp_arm" "$new_arm_url"; then
                echo "Failed to download ARM file from ${new_arm_url} for ${cask_token}."
                return
            fi
            new_arm_sha=$(shasum -a 256 "$tmp_arm" | awk '{print $1}')
            rm "$tmp_arm"

            if [ $has_intel -eq 1 ]; then
                new_intel_url="${intel_url/\#{version\}/$latest_version}"
                tmp_intel="/tmp/${cask_token}-intel.dmg"
                if ! curl -f -L -o "$tmp_intel" "$new_intel_url"; then
                    echo "Failed to download Intel file from ${new_intel_url} for ${cask_token}."
                    return
                fi
                new_intel_sha=$(shasum -a 256 "$tmp_intel" | awk '{print $1}')
                rm "$tmp_intel"
            fi
        else
            new_url="${main_url/\#{version\}/$latest_version}"
            tmp_file="/tmp/${cask_token}.dmg"
            if ! curl -f -L -o "$tmp_file" "$new_url"; then
                echo "Failed to download file from ${new_url} for ${cask_token}."
                return
            fi
            new_sha=$(shasum -a 256 "$tmp_file" | awk '{print $1}')
            rm "$tmp_file"
        fi

        # Update the cask file
        sed -i '' "s/^  version .*/  version \"${latest_version}\"/" "$cask_file"
        if [ $has_arch -eq 0 ]; then
            sed -i '' "/on_arm do/,/end/ s/^    sha256 .*/    sha256 \"${new_arm_sha}\"/" "$cask_file"
            if [ $has_intel -eq 1 ]; then
                sed -i '' "/on_intel do/,/end/ s/^    sha256 .*/    sha256 \"${new_intel_sha}\"/" "$cask_file"
            fi
        else
            sed -i '' "s/^  sha256 .*/  sha256 \"${new_sha}\"/" "$cask_file"
        fi

        # Git operations
        cd "${TAP_PATH}"
        git add "Casks/${cask_token}.rb"
        git commit -m "Update ${cask_token} to ${latest_version}" || true  # Ignore if no changes (though unlikely)

        # Upgrade the app
        echo "Upgrading ${cask_token}..."
        brew upgrade --cask "${TAP_OWNER}/${TAP_REPO}/${cask_token}"
    }

    cd "${TAP_PATH}"

    if [ -z "$CASK_TOKEN" ]; then
        # Update all casks
        for cask_file in "${CASK_DIR}"/*.rb; do
            if [ -f "$cask_file" ]; then
                cask_token=$(basename "$cask_file" .rb)
                update_cask "$cask_token"
            fi
        done
    else
        # Update specific cask
        update_cask "$CASK_TOKEN"
    fi

    # Push all changes
    echo "Pushing updates to GitHub..."
    git push origin main || echo "No changes to push."

    echo "--- Homebrew Cask Update Complete! ---"
    exit 0
fi

# Creation mode (original logic follows)

# Generate cask content
CASK_CONTENT="cask \"${CASK_TOKEN}\" do
  version \"${VERSION}\"

  desc \"${DESCRIPTION}\"
  homepage \"${HOMEPAGE}\"

  livecheck do
    url \"https://github.com/${TAP_OWNER}/${CASK_TOKEN}/releases/latest\"
    strategy :github_latest
  end
"

if [ -n "$INTEL_URL" ] && [ -n "$INTEL_SHA256" ]; then
    CASK_CONTENT+="
  sha256 \"no_check\" # This will be replaced by architecture-specific shas if both are provided

  on_arm do
    url \"${ARM_URL}\"
    sha256 \"${ARM_SHA256}\"
  end

  on_intel do
    url \"${INTEL_URL}\"
    sha256 \"${INTEL_SHA256}\"
  end
"
else
    CASK_CONTENT+="
  url \"${ARM_URL}\"
  sha256 \"${ARM_SHA256}\"
"
fi

CASK_CONTENT+="
  app \"${APP_NAME}\"

  uninstall quit: \"${QUIT_ID}\"

  zap trash: [
    \"~/Library/Application Support/${APP_NAME}\",
    \"~/Library/Caches/com.${CASK_TOKEN}\",
    \"~/Library/Preferences/com.${CASK_TOKEN}.plist\",
    \"~/Library/Saved Application State/com.${CASK_TOKEN}.savedState\",
  ]
end
"

echo "--- Cask file content generated ---"

# Cask File Creation and Placement
echo "Creating Casks directory if it doesn't exist: ${CASK_DIR}"
mkdir -p "${CASK_DIR}"

CASK_FILE="${CASK_DIR}/${CASK_TOKEN}.rb"
echo "Writing cask file to ${CASK_FILE}"
echo "${CASK_CONTENT}" > "${CASK_FILE}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to write cask file."
    exit 1
fi

# Git Operations
echo "Navigating to tap repository: ${TAP_PATH}"
cd "${TAP_PATH}"

echo "Adding new cask file to git..."
git add "Casks/${CASK_TOKEN}.rb"
if [ $? -ne 0 ]; then
    echo "Error: Failed to add cask file to git."
    exit 1
fi

echo "Committing changes..."
git commit -m "Add ${APP_NAME} cask" || echo "Warning: No changes to commit (file may already exist)."

echo "Pushing changes to GitHub..."
git push origin main
if [ $? -ne 0 ]; then
    echo "Error: Failed to push changes to GitHub. Please check your git credentials and network connection."
    exit 1
fi

# Install Cask
echo "Installing the new cask: brew install ${TAP_OWNER}/${TAP_REPO}/${CASK_TOKEN}"
brew install "${TAP_OWNER}/${TAP_REPO}/${CASK_TOKEN}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to install cask. Please check the cask file for errors."
    exit 1
fi

echo "--- Homebrew Cask Creation and Installation Complete! ---"
