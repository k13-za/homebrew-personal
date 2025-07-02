#!/bin/bash
set -e
set -u
# THIS IS IN ALPHA USE AT YOUR OWN RISK
# Function to display usage
usage() {
    echo "Usage: $0 --app-name \"App Name\" --cask-token \"cask-token\" --version \"1.0.0\" \\"
    echo "          --arm-url \"https://example.com/app-arm.dmg\" --arm-sha256 \"arm_sha256\" \\"
    echo "          [--intel-url \"https://example.com/app-intel.dmg\" --intel-sha256 \"intel_sha256\"] \\"
    echo "          --homepage \"https://example.com\" --description \"A short description\" \\"
    echo "          --quit-id \"com.example.app\" --tap-owner \"your-github-username\" \\"
    echo "          --tap-repo \"homebrew-your-tap\""
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
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

# Validate required parameters
if [ -z "$APP_NAME" ] || [ -z "$CASK_TOKEN" ] || [ -z "$VERSION" ] || \
   [ -z "$ARM_URL" ] || [ -z "$ARM_SHA256" ] || \
   [ -z "$HOMEPAGE" ] || [ -z "$DESCRIPTION" ] || \
   [ -z "$QUIT_ID" ] || [ -z "$TAP_OWNER" ] || [ -z "$TAP_REPO" ]; then
    echo "Error: Missing required parameters."
    usage
fi

# Check if brew is installed
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed. Please install Homebrew first."
    exit 1
fi

echo "--- Starting Homebrew Cask Creation and Installation ---"

# Determine tap path
BREW_REPOSITORY="$(brew --repository)"
TAP_PATH="${BREW_REPOSITORY}/Library/Taps/${TAP_OWNER}/${TAP_REPO}"
CASK_DIR="${TAP_PATH}/Casks"
CASK_FILE="${CASK_DIR}/${CASK_TOKEN}.rb"

echo "Determined tap path: ${TAP_PATH}"

# Generate cask content
CASK_CONTENT="cask \"${CASK_TOKEN}\" do
  version \"${VERSION}\"
  sha256 \"no_check\" # This will be replaced by architecture-specific shas if both are provided

  desc \"${DESCRIPTION}\"
  homepage \"${HOMEPAGE}\"

  livecheck do
    url \"https://github.com/${TAP_OWNER}/${CASK_TOKEN}/releases/latest\"
    strategy :github_latest
  end
"

if [ -n "$INTEL_URL" ] && [ -n "$INTEL_SHA256" ]; then
    CASK_CONTENT+="
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
  app \"${APP_NAME}.app\"

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
    # Assuming the tap is a GitHub repository
    git clone "https://github.com/${TAP_OWNER}/${TAP_REPO}.git" "${TAP_PATH}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to clone tap repository. Please ensure it exists and you have access."
        exit 1
    fi
else
    echo "Tap repository already exists locally."
fi

# Cask File Creation and Placement
echo "Creating Casks directory if it doesn't exist: ${CASK_DIR}"
mkdir -p "${CASK_DIR}"

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
git commit -m "Add ${APP_NAME} cask"
if [ $? -ne 0 ]; then
    echo "Error: Failed to commit changes. No changes to commit or git error."
    # This might happen if the file already exists and is identical
    # We can choose to ignore this error or handle it specifically
    # For now, let's just warn and continue if it's a "nothing to commit" error
    if ! git status | grep -q "nothing to commit"; then
        exit 1
    fi
fi

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