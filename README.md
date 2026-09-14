# Minecraft server on an iPhone

A working Minecraft 1.8 server implemented entirely in a SwiftUI app. Real client with a real protocol and no server software. The process listening on port 25565 is an iPhone.

No Mac in the middle, no jailbreak or shell. It is an App Store shaped app with a Start button, and when you press it the phone starts answering Minecraft on your network.

## Why

Because the phone has a TCP stack, a Network framework and nothing stopping it.

## What it does

- Server list ping with an MOTD built from the phone's own hardware, player count and a name sample on hover
- Offline mode login, no encryption
- Creative mode
- Keep-alives every 15 seconds
- A 7x7 chunk flat world, one section high, sent on join
- Chat relayed between players
- A text field in the app that types into the game as `[phone]`
- Start and Stop in the app, with the listening address, the port state, connections, joins, leaves and every chat line in a live log

The MOTD: It reads the device model from `uname`, the battery level and charge state from `UIDevice` and the iOS version, and puts them in the server list entry. Sitting in Minecraft's multiplayer menu you can watch the phone's battery drop.

## What it doesn't do

No mobs, no survival, no saving, no authentication.

Players can't see each other. Two people can join and chat, but the server never sends spawn or movement packets for them, so the world looks empty to both.

The world is a prop. Breaking a block changes it on your screen only, because the server ignores the packet. Rejoin and it's back. There is no block store and no tick loop like a regular server has.

## Requirements

Xcode 26 or later, iOS 26 on the device. Minecraft Java 1.8.9, protocol 47.

Runs on iPhone 11 and newer, iPad mini 5 and newer, iPad Air 3 and newer, iPad 8th gen and newer, and iPad Pro 2018 and newer. The simulator works too, but then it's just a Mac serving Minecraft... which is not the point.

Nothing to install other than Xcode. Foundation, Network and SwiftUI ship with the OS.

## Layout

```
McServerApp.swift
Server.swift
Packets.swift
World.swift
Telemetry.swift
ServerView.swift
```

- `Packets` is varints, strings, big endian numbers, position encoding and the packet framer, plus a reader and a stream reassembler.
- `World` is the flat chunk column.
- `Telemetry` is the battery, the thermal state and the model name table.
- `Server` is the listener, the sessions and the packet handlers.
- `ServerView` is the log, the chat field and the Start button.
- `McServerApp` is four lines.

Only `ServerView` and `Telemetry` touch UIKit. The protocol, the framing and the world generator are plain Foundation, so they build anywhere Swift does.

## Setup

1. Open the project in Xcode and set the run destination to your phone, not the simulator.

2. Signing. Select the McServer target, Signing & Capabilities, pick your team. A free Apple ID works. The app expires after seven days on a free account and needs rebuilding, a paid account gets a year.

3. Run it once from Xcode to install. After that, launch it from the home screen. Launching from Xcode means LLDB attaches, and over a wireless connection that can leave you on a black screen for minutes while it resolves symbols from the device. Nothing is wrong, it is just the debugger. Uncheck Debug executable in the scheme if you want Xcode to install and get out of the way.

4. Allow the local network prompt the first time. iOS asks once, and declining it means nothing on your network can see the server.

5. Press Start. The first log line is the address to connect to.

6. Connect to that address in Minecraft 1.8 via Direct Connect, or let LAN scanning find it.

Keep the app in the foreground. iOS suspends backgrounded apps and takes the listener down with them, which drops everyone. The app disables the idle timer while it's open so the screen won't lock on you, so watch the battery.

## How it works

iOS gives you `NWListener`, so a TCP server is a few lines and the OS handles the sockets.

**The main actor.** `Server` is `@MainActor` and every callback hops onto it with `MainActor.assumeIsolated`. Sessions, the log and the player count are all touched from one thread, so there is no locking anywhere. The class is `@Observable`, so appending a log line is what redraws the UI.

**VarInts.** The protocol's variable width integer format, used for every packet length and ID.

**Packet framing.** Length, then packet ID, then payload. TCP is a stream, so packets arrive split across reads or several at once. `PacketStream` buffers whatever arrived and only hands back a packet once all of its declared bytes are present. The read loop drains it until it comes back empty, then asks for more.

**Stages.** A connection starts in handshake and says which of two things it wants. Status gets the JSON server list entry and a ping echo, and the client closes. Login gets a success packet with a random UUID, the world, and a keep-alive task. After that it's in play, where the only packet read is chat.

Everything else the client sends in play is dropped. Movement, digging, inventory, arm swings, all of it. This is the whole reason the world doesn't work, and also the whole reason the server fits in 600 lines.

**Chunks.** The reason this targets 1.8 and not a current version. In 1.8, a chunk section is a flat array of `(id << 4) | meta` shorts, then block light, then sky light, then biomes, and you can send it uncompressed. Modern versions use palette encoded, bit packed longs and expect zlib. The join sequence here is 49 chunks of one section, bedrock, two dirt, grass, air above, fully lit. One column is built once and posted 49 times with different coordinates.

**Join order matters.** Join Game, Spawn Position, Player Abilities, the chunks, then Player Position and Look. The client sits on Loading world until that last one arrives, whatever else it has.

**Keep-alives.** One task per player, a packet every 15 seconds with an incrementing token. Miss them and the client decides the server died about 30 seconds in.

**The address.** Finding the phone's own LAN IP means `getifaddrs` and walking a C linked list, taking the first IPv4 on an `en` or `bridge` interface. This is only used to print the line telling you what to type, but without it you're guessing.

**Stopping properly.** Stop sends everyone a `0x40` Disconnect with a reason before cancelling, so players get kicked with a message instead of a connection reset. Status pings open and drop a connection every few seconds, so leaves are only logged for sessions that made it to play, or the log is nothing else.

## Licence

MIT. Do what you like with it.
