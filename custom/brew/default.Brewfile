# spinofin default Brewfile -- host-side CLI tools, installed at runtime with:
#   ujust install-default-apps
# Not baked into the image. For the rules on what goes here vs. the Kali
# container vs. pipx, see "Forking spinofin" in the README.

# Recon / web enumeration
brew "subfinder"
brew "amass"
brew "httpx"          # ProjectDiscovery httpx -- do NOT `pipx install httpx`, it shadows this binary
brew "nuclei"
brew "ffuf"
brew "feroxbuster"
brew "gobuster"

# ProjectDiscovery recon suite
brew "katana"
brew "dnsx"
brew "mapcidr"
brew "asnmap"
brew "cdncheck"
brew "tlsx"
brew "uncover"
brew "massdns"
brew "shuffledns"     # requires massdns (shells out to it at runtime)

# Web application testing
brew "nikto"
brew "dalfox"
brew "gau"

# Secret / credential discovery
brew "trufflehog"
brew "gitleaks"

# TLS/SSL inspection
brew "sslscan"
brew "testssl"

# Traffic interception / proxying
brew "proxify"

# Offline password cracking
brew "john-jumbo"     # provides `john`; conflicts with the plain `john` formula -- declare only one
brew "hashcat"

# Online login attacks
brew "hydra"
brew "ncrack"

# Port scanning
brew "rustscan"       # connect scanner; pair with the container's nmap (`kali nmap ...`), not its default auto-nmap

# Exploit reference
brew "exploitdb"      # provides `searchsploit`

# Pivoting / proxying
brew "proxychains-ng" # provides `proxychains4`
brew "chisel-tunnel"  # provides the `chisel` binary (formula renamed; `chisel` is a different, macOS-only tool)

# Networking utilities
brew "netcat"
brew "rlwrap"

# Python tooling bootstrap
brew "pipx"           # installer for the host-side pipx bucket (custom/pipx/*.pipx)
