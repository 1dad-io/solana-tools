# solana-tools

A Bash Swiss Army knife to operate a Solana validator.

It started as a few helper functions and kept growing together with my validator setup. Most of the logic still lives in `solana.sh`. It handles setup, updates, restarts, snapshots, RPC helpers, host tuning and failover between a staked validator and an unstaked standby.

This repo follows the setup I actually run, so some parts are intentionally opinionated. Security comes first, then reliability and performance. I try to keep the code simple after that.

> [!WARNING]
> This is operator tooling, not a turnkey validator installer. Read the config and systemd units before running `setup`. It can change SSH, UFW, fail2ban, sudoers, systemd, kernel and network settings, and validator keypair layout.

## Setup

`solana.sh` is the main entry point. Local settings live in `solana-tools.conf`, which is created from `etc/default/solana-tools.conf` on first run.

The validator command line stays in systemd. The script reads the selected unit and reuses its identity, vote account, ledger, ports and client options instead of keeping another copy of the validator config.

Clone the repo as the user that will operate the validator:

```bash
git clone https://github.com/1dad-io/solana-tools.git ~/solana-tools
cd ~/solana-tools
./solana.sh -h
```

Review `solana-tools.conf` and the systemd unit you are going to use, then run:

```bash
./solana.sh setup
```

For an unstaked standby:

```bash
./solana.sh setup --unstaked
```

`setup` installs or configures the selected client and host prerequisites, copies the selected systemd config into place and applies the enabled security and tuning options.

The repo contains units for mainnet, testnet and devnet. Mainnet and testnet are what I actually operate. The devnet unit is there but has not been part of my validator setup.

## Help

```text
$ ./solana.sh -h
solana-tools 0.1.0

USAGE:
    ./solana.sh <COMMAND> [FLAGS] [OPTIONS] [ARGS]

FLAGS:
    -1, --oneshot                  Make leader/optimistic-slot run only once
    -c, --cron                     Indicate a non-interactive shell (run by cron)
    -D, --dryrun                   Echo commands instead of running them
    -f, --force                    Bypass any errors and confirmation prompts
        --fd                       Make up <COMMAND> for Firedancer
    -h, --help                     Print this help and exit
    -n, --now                      Don't wait for the restart window
    -p, --poll                     Poll the RPC server for <COMMAND> to succeed
    -q, --quiet                    Suppress informational output
        --reboot                   Reboot server within the restart window
        --unstaked                 Setup a non-voting validator (used in <setup>)

OPTIONS:
        --clean [dir1,dirN|all]    Clean validator data within the restart window [example: --clean=ledger,accounts]
    -g, --governor <GOVERNOR>      CPUFreq governor to override the one set in the config [default: disabled]
    -d, --max-delinquent-stake <%> The maximum delinquent stake % permitted for a restart [default: 5]
    -i, --min-idle-time <MINUTES>  Minimum time that the validator should not be leader before restarting [default: 10]
        --move <SOURCE> <DEST>     Move files within the restart window [example: --move /path/to/source /destination]
        --link <TARGET> <NAME>     Link files within the restart window [example: --link /path/to/target /link_name]
    -u, --url <URL_OR_MONIKER>     URL for Solana's JSON RPC or moniker to override the config [default: mainnet-beta]
    -v, --version <VERSION>        Version to install [default: version tagged in the systemd unit file]

COMMANDS:
        airdrop [ADDRESS] [-p]     Request airdrop of 1 SOL [default: identity]
        balance [ADDRESS]          Rebalance accounts with the step amount [default: balance_to]
        bind [HOST] [PUBKEY]       Pair the remote validator for identity transition
        check-snapshot [NUM_SLOTS] Check if snapshot is less than this many slots behind [default: 2500]
        cpu-tuner [GOVERNOR]       Tune CPU settings for the given governor [default: schedutil]
        dz [SUBCOMMAND]            Run doublezero with any: up/down/pda/fees/fund/init/setup/user
        export <bin|log|tower>     Export environment variables
        jito-reload                Hot reload the Jito configuration
        leader-slot [-1]           Show countdown to the next leader slot
        make-snapshot <SLOT>       Create a new ledger snapshot for the given slot
        monitor [--fd]             Monitor the validator
        on-boot                    Set a reboot flag for the watchdog (run by cron)
        optimistic-slot [-1]       Show optimistic slot
        rakurai-status             Show runtime status information about rakurai
        relayer [status]           Run relayer (only used by systemd)
        restart [restart flags]    Restart validator safely within the restart window
        restart-relayer [--now]    Restart relayer safely within the restart window
        rxtower                    Transition identity from the voting validator
        setup [--unstaked]         Setup a validator by installing prerequisites
        slots [EPOCH] [-q]         Show leader schedule (use -q for a quick view)
        stakes                     Fetch the validator stakes by the vote account
        start [EPOCH]              Start the validator at epoch boundary, or now
        stop  [EPOCH]              Stop the validator at epoch boundary, or now
        sys-tuner                  Tune system settings
        trim [-f]                  Trim all mounted FS safely within the restart window
        txtower [REMOTE_HOST]      Transition identity to a non-voting validator [default: ssh_host]
        unswap                     Free swap by swapping back into RAM
        update [--fd]              Update validator safely within the restart window
        update-relayer             Update relayer safely within the restart window
        usage                      Summarize disk usage of validator data
        validator [status]         Run the validator (only used by systemd)
        vote-off                   Stop voting by setting unstaked identity
        vote-on [EPOCH]            Start voting at epoch boundary, or now
        wait-for-restart           Monitor the validator for a good time to restart
        watchdog [off|on|status]   Run the failover watchdog (run by cron)

The default command is -h
```

## Failover

This is the part of the project I care about most.

A pair has one staked validator and one unstaked standby. `bind` configures the peer used by `txtower`, `rxtower` and watchdog.

For a planned move, `txtower` copies the consensus file once while the staked validator is still voting. That first copy is only an SCP preflight. If it fails, voting is left untouched. The staked validator then switches to its unstaked identity, the final consensus state is copied again and `rxtower` starts voting on the standby.

The receiving validator keeps its persistent identity pointing to the unstaked key until `set-identity` succeeds. This is deliberate. I have seen `set-identity` fail badly enough to restart the validator, and in that case it must come back unstaked rather than start a second copy of the voting identity.

Watchdog uses the same transition path. While staked it watches local health. While unstaked it watches the staked validator and its delinquency state. After a failover it waits for a recheck before taking any action in the new role.

Mainnet still uses Tower BFT tower files. Testnet uses Alpenglow vote history. A forced Alpenglow takeover without vote history is only allowed after the standby has caught up to the processed tip and finalized past the previous staked validator's last vote.

Do not enable unattended failover until SSH, identities, filesystem paths and watchdog state have been tested on your own setup.

## Files

```text
solana.sh                       main CLI
etc/default/                    default config and messages
etc/{ssh,ufw,fail2ban,...}/     host and security config
mainnet/                        mainnet systemd units and genesis
testnet/                        testnet systemd units, config and genesis
devnet/                         devnet systemd unit
scripts/                        helper scripts
keys/                           runtime key material, ignored by Git
crontab                         unattended jobs
.bash_aliases                   shell shortcuts
```

Runtime key material is expected under `keys/`. Keypair JSONs and relayer key material there are ignored by Git.

## Status

Issues and PRs are welcome, especially for security, reliability or performance improvements that do not add unnecessary complexity.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
