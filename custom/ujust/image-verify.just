# vim: set ft=make :
########################
### image-verify.just
########################
## Verifies spinofin's own OCI image signature (keyless cosign/OIDC via
## Fulcio) from the host. README's "Optional: Enable Image Signing" section
## already documents the raw `cosign verify` command by hand, but a pentesting
## OS shouldn't make you copy-paste a verification command from a README).

spinofin_image := "ghcr.io/zoeruda/spinofin"

# Verify spinofin's cosign signature. No arg: verifies what's ACTUALLY BOOTED right now, by digest. "stable"/"testing": checks that tag's current registry content instead.
[group('Security')]
verify-image tag="auto":
    #!/usr/bin/env bash
    set -euo pipefail

    ensure_cosign() {
        if command -v cosign >/dev/null 2>&1; then
            return 0
        fi
        echo "cosign is not installed."
        if command -v brew >/dev/null 2>&1; then
            if gum confirm "Install cosign via Homebrew?"; then
                brew install cosign
            else
                echo "Cannot verify without cosign. Aborting."
                exit 1
            fi
        else
            echo "ERROR: cosign not found and brew is unavailable." >&2
            echo "Run 'ujust install-default-apps' first, or install cosign" >&2
            echo "yourself: https://docs.sigstore.dev/cosign/system_config/installation/" >&2
            exit 1
        fi
    }

    do_verify() {
        # $1 = the exact cosign reference to check (a ":tag" or "@digest" pull spec)
        cosign verify \
            --certificate-identity-regexp="https://github.com/zoeruda/spinofin/.github/workflows/" \
            --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
            "$1"
    }

    unsigned_notice() {
        echo "':testing' images are intentionally left unsigned (see README's"
        echo "\"How to Get Started with spinofin\" section) -- there is"
        echo "nothing to verify."
    }

    case "{{ tag }}" in
        auto)
            if ! command -v bootc >/dev/null 2>&1; then
                echo "ERROR: 'bootc' not found -- this doesn't look like a bootc system." >&2
                exit 1
            fi
            if ! command -v jq >/dev/null 2>&1; then
                echo "ERROR: 'jq' not found -- needed to parse 'bootc status'." >&2
                exit 1
            fi

            # `bootc status` needs root to read deployment state -- confirmed
            # on real spinofin hardware (unprivileged call fails with
            # "Querying root privilege: This command must be executed as the
            # root user"), so go straight to sudo instead of trying plain
            # first and eating an extra prompt/round-trip on every run.
            status_json="$(sudo bootc status --format json)"

            booted_transport="$(printf '%s' "${status_json}" | jq -r '.status.booted.image.image.transport // empty')"
            booted_spec="$(printf '%s' "${status_json}" | jq -r '.status.booted.image.image.image // empty')"
            booted_digest="$(printf '%s' "${status_json}" | jq -r '.status.booted.image.imageDigest // empty')"

            if [ -z "${booted_spec}" ] || [ -z "${booted_digest}" ]; then
                echo "ERROR: could not read the booted image from 'bootc status'." >&2
                echo "Check an explicit tag instead: ujust verify-image stable" >&2
                exit 1
            fi
            if [ "${booted_transport}" != "registry" ]; then
                echo "The booted image wasn't pulled from a registry (transport:"
                echo "'${booted_transport}', e.g. a local 'just build') -- there's"
                echo "nothing on a registry to cosign-verify it against."
                exit 0
            fi

            booted_repo="${booted_spec%:*}"
            booted_tag="${booted_spec##*:}"

            if [ "${booted_repo}" != "{{ spinofin_image }}" ]; then
                echo "NOTE: the booted image is '${booted_spec}', not {{ spinofin_image }}."
                echo "(Stock Bluefin, a rollback, or a fork -- verifying it anyway.)"
            fi

            if [ "${booted_tag}" = "testing" ]; then
                unsigned_notice
                echo "You're currently booted into :testing (digest ${booted_digest})."
                exit 0
            fi

            ensure_cosign
            echo "Verifying the currently BOOTED image: ${booted_spec}"
            echo "  pinned to its exact digest: ${booted_digest}"
            do_verify "${booted_repo}@${booted_digest}"
            ;;
        testing)
            unsigned_notice
            echo "(Checked here because you asked for ':testing' explicitly. Run"
            echo "'ujust verify-image' with no argument to check what's actually booted.)"
            exit 0
            ;;
        *)
            ensure_cosign
            echo "Verifying {{ spinofin_image }}:{{ tag }}'s CURRENT content in the"
            echo "registry -- this is what a fresh 'bootc switch'/'bootc upgrade' would"
            echo "pull right now. It is NOT necessarily what's booted on this machine;"
            echo "run 'ujust verify-image' with no argument to check that instead."
            do_verify "{{ spinofin_image }}:{{ tag }}"
            ;;
    esac
