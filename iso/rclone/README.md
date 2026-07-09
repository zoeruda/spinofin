# Rclone Configuration Directory

This directory contains example rclone configuration files for uploading ISO images to various cloud storage providers.

## Available Configurations

- **cloudflare-r2.conf** - Cloudflare R2 (S3-compatible, zero egress fees)
- **aws-s3.conf** - Amazon S3 (highly reliable, standard pricing)
- **backblaze-b2.conf** - Backblaze B2 (affordable, low egress fees)
- **sftp.conf** - SFTP/SSH upload to any server
- **scp.conf** - SCP upload to any server

## How to Use

### 1. Choose Your Storage Provider

Select the configuration file that matches your preferred storage provider. Each file contains:

- Setup instructions
- Required GitHub secrets
- Provider-specific configuration options

### 2. Building ISO/Disk Images (Manual, Local Process)

**There is currently no `build-disk.yml` GitHub Actions workflow in this repository** — ISO and disk image building is a manual, local process using [`bootc-image-builder`](https://github.com/osbuild/bootc-image-builder) against `iso/iso.toml` (Anaconda installer ISO) or `iso/disk.toml` (qcow2/raw/other disk formats). If you'd like CI-automated builds and uploads, that would need to be built as a new workflow — see "Automating This" below.

Example, run locally with root/privileged Podman **from the repository root** (adjust the image reference for your fork). Two things this needs that are easy to miss:

- **Pull the image into local root storage first.** `bootc-image-builder` reads from the container storage mounted at `/var/lib/containers/storage` — it does not pull the target image itself, so `sudo podman pull` your image before running the build, or it won't find it.
- **`--rootfs btrfs`.** Fedora-based bootc images generally don't embed a default root filesystem type, so `bootc-image-builder` requires `--rootfs` to be set explicitly (`error: cannot build manifest: no default root filesystem type specified`). Fedora's desktop variants (Workstation, Silverblue — what Bluefin/spinofin are built on) have defaulted to `btrfs` since Fedora 33; Fedora Server/CoreOS default to `xfs` instead, which is a different lineage and not what you want here.

```bash
sudo podman pull ghcr.io/zoeruda/spinofin:stable

mkdir -p output
sudo podman run --rm -it --privileged --pull=newer \
  --network=host \
  --security-opt label=type:unconfined_t \
  -v ./iso/iso.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type anaconda-iso \
  --rootfs btrfs \
  --config /config.toml \
  ghcr.io/zoeruda/spinofin:stable
```

Use `--config iso/disk.toml` with `--type qcow2` (or `raw`, `vmdk`, `vhd`) to build a disk/VM image instead of an installer ISO. See the [bootc-image-builder documentation](https://github.com/osbuild/bootc-image-builder) for the full set of supported `--type` values and options.

### 3. Uploading the Result (Manual, Using These Configs)

The rclone configuration files in this directory are templates for uploading whatever `bootc-image-builder` produces in `output/` to cloud storage — they are not currently wired into any CI workflow. To use one manually:

```bash
mkdir -p ~/.config/rclone
cp iso/rclone/cloudflare-r2.conf ~/.config/rclone/rclone.conf
# Edit ~/.config/rclone/rclone.conf and replace each ${SECRET_NAME}
# placeholder with your actual credential -- do NOT commit this edited copy.
rclone copy ./output/ cloudflare-r2:your-bucket-name/
```

Swap in whichever provider's `.conf` file matches your setup (`aws-s3.conf`, `backblaze-b2.conf`, `sftp.conf`, `scp.conf`).

### Automating This

If you want CI to build and upload images automatically on a schedule or dispatch trigger, that requires a new `build-disk.yml` workflow that runs `bootc-image-builder` (as a privileged container step) and then `rclone copy` with secrets substituted from GitHub Actions secrets. This isn't implemented in spinofin today; treat the steps above as the manual equivalent until/unless that workflow is written.

## Configuration File Format

All configuration files use the rclone INI format with placeholders for secrets:

```ini
[remote-name]
type = provider_type
access_key_id = ${SECRET_NAME}
secret_access_key = ${ANOTHER_SECRET}
```

The workflow automatically replaces `${SECRET_NAME}` with the corresponding GitHub secret value.

## Customizing Configurations

You can modify these configuration files to suit your needs:

1. Edit the configuration file for your provider
2. Update the secret names in `${...}` placeholders
3. Add the corresponding secrets to your GitHub repository
4. Commit the changes

**Important:** Never commit actual credentials or secrets to the repository. Always use `${SECRET_NAME}` placeholders and GitHub secrets.

## Provider Comparison

| Provider      | Setup Complexity | Cost   | Egress Fees | Notes                          |
| ------------- | ---------------- | ------ | ----------- | ------------------------------ |
| Cloudflare R2 | Medium           | $      | Free        | Best for frequent downloads    |
| AWS S3        | Medium           | $$     | $$          | Most reliable, global reach    |
| Backblaze B2  | Easy             | $      | $           | Good balance of price/features |
| SFTP/SCP      | Medium           | Free\* | Free        | Requires your own server       |

\*Requires existing server infrastructure

## Troubleshooting

### "Permission denied" errors

- Check that your access keys are correct
- Verify IAM permissions (for AWS)
- Ensure the bucket exists and is accessible

### "Endpoint not found" errors

- Verify the endpoint URL is correct
- Check region settings
- For Cloudflare R2, ensure you're using the correct Account ID

### Upload fails silently

- Enable workflow debug logging in GitHub Actions
- Check that secrets are properly set
- Verify the rclone config syntax

## Additional Resources

- [Rclone Documentation](https://rclone.org/docs/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [Backblaze B2 Documentation](https://www.backblaze.com/b2/docs/)

## Need Help?

If you encounter issues:

1. Check the workflow logs in the Actions tab
2. Review the rclone documentation for your provider
3. Ask in the [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
4. Post in the [Universal Blue Forums](https://universal-blue.discourse.group/)
