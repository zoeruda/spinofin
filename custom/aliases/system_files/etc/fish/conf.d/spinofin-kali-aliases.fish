# spinofin: shell functions for spinofin-kali in fish shell
# Baked into the image -- automatically sourced by fish from /etc/fish/conf.d/

function _spinofin_kali_check
    if not command -q distrobox
        echo "spinofin: distrobox not found on host." >&2
        return 1
    end
    if not distrobox list --root 2>/dev/null | grep -q "spinofin-kali"
        echo "spinofin: the 'spinofin-kali' container doesn't exist yet." >&2
        echo "Run 'ujust setup-kali' first, then try again." >&2
        return 1
    end
end

function kali --description "Run command in spinofin-kali container as user"
    _spinofin_kali_check; or return 1
    if test (count $argv) -eq 0
        distrobox enter --root --no-workdir spinofin-kali; or true
    else
        distrobox enter --root spinofin-kali -- $argv
    end
end

function kalisudo --description "Run command in spinofin-kali container as root"
    _spinofin_kali_check; or return 1
    distrobox enter --root spinofin-kali -- sudo $argv
end

function iskali --description "Check if spinofin-kali container exists"
    if not command -q distrobox
        echo "spinofin: distrobox not found on host." >&2
        return 2
    end
    if distrobox list --root 2>/dev/null | grep -q "spinofin-kali"
        echo "spinofin-kali: present"
        return 0
    end
    echo "spinofin-kali: not created yet -- run 'ujust setup-kali'"
    return 1
end
