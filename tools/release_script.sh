#!/usr/bin/env bash
set -euo pipefail

REPO="puma/puma"
VERSION_FILE="lib/puma/const.rb"
HISTORY_FILE="History.md"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}==>${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}==>${NC} %s\n" "$*"; }
error() { printf "${RED}==>${NC} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

CACHE_DIR=""
cleanup() { [[ -n "$CACHE_DIR" ]] && rm -rf "$CACHE_DIR"; }
trap cleanup EXIT

check_deps() {
  local missing=()
  command -v communique >/dev/null 2>&1 || missing+=("communique")
  command -v gh >/dev/null 2>&1 || missing+=("gh")
  command -v jq >/dev/null 2>&1 || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required dependencies: ${missing[*]}"
  fi
}

current_version() {
  sed -n 's/.*PUMA_VERSION = VERSION = "\(.*\)".*/\1/p' "$VERSION_FILE"
}

last_tag() {
  git tag --sort=-v:refname | grep -E '^v[0-9]' | head -1
}

bump_version() {
  local version="$1" bump_type="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$bump_type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) die "Unknown bump type: $bump_type" ;;
  esac
}

ensure_clean_main() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  [[ "$branch" == "main" ]] || die "Must be on 'main' branch (currently on '$branch')"

  [[ -z "$(git status --porcelain)" ]] || die "Working directory not clean. Commit or stash first."

  git fetch origin --quiet
  local local_sha remote_sha
  local_sha=$(git rev-parse HEAD)
  remote_sha=$(git rev-parse origin/main)
  [[ "$local_sha" == "$remote_sha" ]] || die "Local main differs from origin/main. Pull or push first."
}

check_ci() {
  info "Checking CI status for HEAD..."
  local sha
  sha=$(git rev-parse HEAD)
  local status
  status=$(gh api "repos/$REPO/commits/$sha/check-runs" \
    --jq '[.check_runs[] | select(.conclusion != null)] |
      if length == 0 then "pending"
      elif all(.conclusion == "success") then "success"
      else "failure" end' 2>/dev/null) || status="unknown"

  case "$status" in
    success) info "CI is green." ;;
    pending) warn "CI is still running. Proceed with caution." ;;
    failure) warn "CI has failures. You may want to investigate before releasing." ;;
    *)       warn "Could not determine CI status." ;;
  esac
}

# Look up a GitHub user's display name, with file-based caching.
get_user_name() {
  local login="$1"
  local cache_file="$CACHE_DIR/$login"
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    return
  fi
  local name
  name=$(gh api "users/$login" --jq '.name // empty' 2>/dev/null) || true
  name="${name:-$login}"
  printf '%s' "$name" > "$cache_file"
  echo "$name"
}

# Generate a single link reference line for a PR or issue.
generate_link_ref() {
  local num="$1"
  local data login

  if data=$(gh pr view "$num" --repo "$REPO" --json mergedAt,author 2>/dev/null); then
    login=$(echo "$data" | jq -r '.author.login')
    local merged_at author_name
    merged_at=$(echo "$data" | jq -r '.mergedAt' | cut -dT -f1)
    author_name=$(get_user_name "$login")
    printf '[#%s]:https://github.com/%s/pull/%s     "PR by %s, merged %s"\n' \
      "$num" "$REPO" "$num" "$author_name" "$merged_at"
    return
  fi

  if data=$(gh issue view "$num" --repo "$REPO" --json closedAt,author 2>/dev/null); then
    login=$(echo "$data" | jq -r '.author.login')
    local closed_at
    closed_at=$(echo "$data" | jq -r '.closedAt' | cut -dT -f1)
    printf '[#%s]:https://github.com/%s/issues/%s     "Issue by @%s, closed %s"\n' \
      "$num" "$REPO" "$num" "$login" "$closed_at"
    return
  fi

  warn "Could not look up #$num"
}

# Parse PR/issue numbers from changelog text, generate link refs for any
# that don't already exist in History.md.
generate_all_link_refs() {
  local changelog="$1"
  CACHE_DIR=$(mktemp -d)

  local numbers
  numbers=$(echo "$changelog" | grep -oE '\[#[0-9]+\]' | sed 's/\[#//;s/\]//' | sort -rn -u)

  local refs=""
  for num in $numbers; do
    if grep -q "^\[#${num}\]:" "$HISTORY_FILE" 2>/dev/null; then
      continue
    fi
    info "  Looking up #$num..."
    local ref
    ref=$(generate_link_ref "$num") || true
    if [[ -n "$ref" ]]; then
      refs+="$ref"$'\n'
    fi
  done
  printf '%s' "$refs"
}

# Insert link references before the existing block at the bottom of History.md.
insert_link_refs() {
  local refs="$1"
  [[ -z "$refs" ]] && return

  local first_ref_line
  first_ref_line=$(grep -n '^\[#[0-9]' "$HISTORY_FILE" | head -1 | cut -d: -f1)

  if [[ -z "$first_ref_line" ]]; then
    printf '\n%s' "$refs" >> "$HISTORY_FILE"
  else
    local tmpfile
    tmpfile=$(mktemp)
    head -n $((first_ref_line - 1)) "$HISTORY_FILE" > "$tmpfile"
    printf '%s' "$refs" >> "$tmpfile"
    tail -n +"$first_ref_line" "$HISTORY_FILE" >> "$tmpfile"
    mv "$tmpfile" "$HISTORY_FILE"
  fi
}

# Extract the changelog section for a given version from History.md.
extract_history_section() {
  local version="$1"
  awk "/^## ${version//./\\.} /{found=1; next} /^## /{if(found) exit} found" "$HISTORY_FILE"
}

cmd_prepare() {
  check_deps
  ensure_clean_main
  check_ci

  local last new_version bump_type
  last=$(last_tag)
  info "Last release tag: $last"
  echo ""

  echo "What type of release is this?"
  echo "  1) patch  - bug fixes only"
  echo "  2) minor  - new features, backward compatible"
  echo "  3) major  - breaking changes"
  echo ""
  read -rp "Enter choice [1/2/3]: " choice

  case "$choice" in
    1) bump_type="patch" ;;
    2) bump_type="minor" ;;
    3) bump_type="major" ;;
    *) die "Invalid choice: $choice" ;;
  esac

  local current
  current=$(current_version)
  new_version=$(bump_version "$current" "$bump_type")
  info "Version bump: $current -> $new_version"

  # Codename earner for minor/major releases
  local earner=""
  if [[ "$bump_type" != "patch" ]]; then
    echo ""
    info "Top contributors since $last:"
    git shortlog -s -n --no-merges "$last..HEAD" | head -5
    earner=$(git shortlog -s -n --no-merges "$last..HEAD" | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    echo ""
    info "Codename earner: $earner"
  fi

  # Create temporary tag so communiqué can compute the diff range
  local new_tag="v${new_version}"
  info "Creating temporary tag $new_tag..."
  git tag "$new_tag" HEAD

  info "Generating changelog with communiqué (this may take a minute)..."
  # Let communiqué use the gh CLI's existing auth
  export GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"

  local changelog
  if ! changelog=$(communique generate "$new_tag" "$last" --concise --dry-run 2>/dev/null); then
    git tag -d "$new_tag" >/dev/null 2>&1
    die "communiqué failed. Is ANTHROPIC_API_KEY set?"
  fi

  git tag -d "$new_tag" >/dev/null 2>&1

  # Safety: convert any inline links the LLM may have used to reference-style
  changelog=$(echo "$changelog" | sed 's/\[#\([0-9]*\)\](https:\/\/[^)]*)/[#\1]/g')

  echo ""
  info "Generated changelog:"
  echo "---"
  echo "$changelog"
  echo "---"
  echo ""

  # Link references
  info "Generating link references..."
  local link_refs
  link_refs=$(generate_all_link_refs "$changelog")

  # Prepend new section to History.md
  local today
  today=$(date +%Y-%m-%d)
  local header="## ${new_version} / ${today}"

  info "Updating $HISTORY_FILE..."
  local tmpfile
  tmpfile=$(mktemp)
  printf '%s\n\n%s\n\n' "$header" "$changelog" > "$tmpfile"
  cat "$HISTORY_FILE" >> "$tmpfile"
  mv "$tmpfile" "$HISTORY_FILE"

  if [[ -n "$link_refs" ]]; then
    insert_link_refs "$link_refs"
  fi

  # Bump version
  info "Updating $VERSION_FILE..."
  sed -i '' "s/PUMA_VERSION = VERSION = \".*\"/PUMA_VERSION = VERSION = \"${new_version}\"/" "$VERSION_FILE"

  if [[ "$bump_type" != "patch" ]]; then
    sed -i '' 's/CODE_NAME = ".*"/CODE_NAME = "PUT CODENAME HERE"/' "$VERSION_FILE"
  fi

  # Branch, commit, PR
  local branch="release-v${new_version}"
  info "Creating branch $branch..."
  git checkout -b "$branch"
  git add "$VERSION_FILE" "$HISTORY_FILE"
  git commit --no-gpg-sign -m "Release v${new_version}"
  git push -u origin "$branch"

  local pr_body=""
  if [[ -n "$earner" ]]; then
    pr_body="@${earner} earned the codename for this release. Please propose a codename!"
  fi

  info "Creating pull request..."
  local pr_url
  pr_url=$(gh pr create --repo "$REPO" --title "Release v${new_version}" --body "$pr_body")

  echo ""
  info "Release PR created: $pr_url"
  [[ -n "$earner" ]] && warn "Waiting on @$earner for a codename before merging."
  echo ""
  echo "Next steps:"
  echo "  1. Review and merge the PR"
  echo "  2. Run: tools/release_script.sh build"
}

cmd_build() {
  check_deps
  ensure_clean_main

  local version tag
  version=$(current_version)
  tag="v${version}"

  info "Building Puma $version..."

  info "Creating and pushing tag $tag..."
  git tag --no-sign "$tag"
  git push origin "$tag"

  info "Building MRI gem..."
  bundle exec rake build

  echo ""
  info "Built: pkg/puma-${version}.gem"
  echo ""
  echo "To build the JRuby gem:"
  echo "  1. Switch to JRuby"
  echo "  2. rake java gem"
  echo ""
  echo "Then push:"
  echo "  gem push pkg/puma-${version}.gem"
  echo "  gem push pkg/puma-${version}-java.gem"
  echo ""
  echo "After pushing, run: tools/release_script.sh github"
}

cmd_github() {
  check_deps

  local version tag
  version=$(current_version)
  tag="v${version}"

  info "Creating GitHub release for $tag..."

  local body
  body=$(extract_history_section "$version")
  [[ -n "$body" ]] || die "Could not find section for $version in $HISTORY_FILE"

  gh release create "$tag" \
    --repo "$REPO" \
    --title "$tag" \
    --notes "$body"

  info "GitHub release published: https://github.com/$REPO/releases/tag/$tag"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  prepare   Generate changelog, bump version, open release PR
  build     Tag release and build gem files
  github    Create GitHub release from History.md
EOF
  exit 1
}

case "${1:-}" in
  prepare) cmd_prepare ;;
  build)   cmd_build ;;
  github)  cmd_github ;;
  *)       usage ;;
esac
