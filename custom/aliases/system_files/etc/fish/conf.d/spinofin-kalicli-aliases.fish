# spinofin: shell functions for kalicli in fish shell
# Baked into the image -- automatically sourced by fish from /etc/fish/conf.d/

function _spinofin_kalicli_check
    if not command -q podman
        echo "spinofin: podman not found on host." >&2
        return 1
    end
    if not podman image exists localhost/spinofin-kalicli:latest 2>/dev/null
        echo "spinofin: the 'kalicli' image isn't built yet." >&2
        echo "Run 'ujust setup-kalicli' first, then try again." >&2
        return 1
    end
    if not systemctl --user is-active --quiet spinofin-kalicli 2>/dev/null
        if not systemctl --user start spinofin-kalicli >/dev/null 2>&1
            echo "spinofin: failed to start the 'kalicli' service." >&2
            echo "Check 'systemctl --user status spinofin-kalicli'." >&2
            return 1
        end
    end
end

function kalicli --description "Run command in rootless kalicli container"
    _spinofin_kalicli_check; or return 1

    set -l exec_flags -i
    if test -t 0; and test -t 1
        set -a exec_flags -t
    end

    if test (count $argv) -eq 0
        podman exec $exec_flags spinofin-kalicli /bin/bash -l
    else
        podman exec $exec_flags spinofin-kalicli $argv
    end
end

function iskalicli --description "Check if kalicli container is built/running"
    if not command -q podman
        echo "spinofin: podman not found on host." >&2
        return 2
    end
    if podman image exists localhost/spinofin-kalicli:latest 2>/dev/null
        if systemctl --user is-active --quiet spinofin-kalicli 2>/dev/null
            echo "kalicli: present (running)"
        else
            echo "kalicli: present (stopped -- 'kalicli' will start it on demand)"
        end
        return 0
    end
    echo "kalicli: not set up yet -- run 'ujust setup-kalicli'"
    return 1
end
