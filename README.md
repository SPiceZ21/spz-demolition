# spz-demolition

> Demolition derby: last car running wins.

![version](https://img.shields.io/badge/version-1.0.0-ff6200) ![SPiceZ-Core](https://img.shields.io/badge/SPiceZ--Core-beta-18181b)

## Overview

A destruction derby in the demolition bowl with real damage.

## Features

- Real vehicle damage
- Last car running wins

## Requirements

| Resource | Type |
|---|---|
| `ox_lib` | third-party |
| `spz-minigames` | SPiceZ module |
| `oxmysql` | third-party |
| `spz-core` | SPiceZ module |
| `spz-identity` | SPiceZ module |
| `iak_demolition` | third-party |

## Installation

Included in the [txAdmin recipe](https://github.com/SPiceZ21/spz-txrecipe). Manual install:

1. Download `spz-demolition` from GitHub (latest release, or the repository) into your `resources` folder.
2. Add to `server.cfg`, after its requirements:

```cfg
ensure spz-demolition
```

## Configuration

- `config.lua`

See the file for every option.

## Commands

| Command | Who | Description |
|---|---|---|
| `/dmwhere` | dev | Print arena position info |

## Notes

- Requires the `iak_demolition` arena map (third-party, not included).

---

Part of **SPiceZ-Core** — [documentation](https://github.com/SPiceZ21/Docs) · [all modules](https://github.com/SPiceZ21/Docs/blob/main/modules/README.md)
