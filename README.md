# SBPP BaseVotes

A fork of SourceMod's Basic Votes plugin designed to integrate with [SourceBans++](https://github.com/sbpp/sourcebans-pp).

## What is this?

The stock SourceMod basevotes plugin doesn't support SourceBans++ or SourceComms++. This fork bridges that gap by:

- Using `SBPP_BanPlayer()` instead of stock `BanClient()` for votebans
- Using `SourceComms_SetClientMute()` and `SourceComms_SetClientGag()` for comms restrictions
- Providing forwards for external plugins to hook into vote events
- Supporting player selection menus when commands are used without arguments

## Vote Commands

- `!votekick` / `sm_votekick` - Initiate a kick vote
- `!voteban` / `sm_voteban` - Initiate a ban vote (uses SourceBans++)
- `!votemute` / `sm_votemute` - Initiate a voice mute vote (uses SourceComms++)
- `!votegag` / `sm_votegag` - Initiate a text gag vote (uses SourceComms++)
- `!votemap` / `sm_votemap` - Initiate a map change vote
- `!vote` / `sm_vote` - Create a custom yes/no or multiple-choice vote

All commands can be used with or without arguments - no arguments opens a player selection menu.

## API Forwards

The plugin exposes several forwards for tracking vote activity:

```sourcepawn
forward Action SBPP_OnVoteInitiated(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason);
forward void SBPP_OnVoteInitiated_Post(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason);
forward void SBPP_OnPlayerVoted(int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName);
forward void SBPP_OnVoteEnded(SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, int iVotesTotal, float fPercentage);
forward Action SBPP_OnVoteActionExecute(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iDuration);
forward void SBPP_OnVoteActionExecute_Post(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sTargetAuth, const char[] sReason, int iDuration);
```

## BaseVotes Control Plugin

`sbpp_basevotes_control.sp` is an optional companion plugin that logs all vote activity to Discord via webhooks using [RipExt](https://github.com/ErikMinekus/sm-ripext).

### Features

- Logs vote initiations with initiator, target, and reason
- Comprehensive vote results with full voter breakdown (who voted yes/no with SteamIDs)
- Tracks punishment executions (kicks, bans, mutes, gags)
- Optional real-time individual vote notifications

### Configuration

```
sm_basevotes_webhook "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
sm_basevotes_control_enabled "1"  // Enable/disable logging (default: 1)
```

The control plugin uses the forwards above to hook into vote events and send formatted embeds to Discord with rich information including voter lists, timestamps, and color-coded results.

