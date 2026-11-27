# Monkey Backrooms VR (Meta Quest 2 / 3 / Pro)

Godot 4 project. Everything (monkey, lobby, maze, UI) is generated from code, so there are no
art assets to import.

## What's in it

- **Monkey player model**: other players see your monkey head, body, tail, arms and name tag.
  Your own hands show as fur-coloured balls.
- **Hand locomotion (gorilla-tag style)**: touch the floor, a wall or the ceiling with a hand and
  push or pull. Your body moves opposite to your hand and keeps its momentum when you let go.
  Fallbacks: left stick walks, right stick snap-turns.
- **Lobby with a computer**: point at it with either controller and pull the trigger.
  - `-` / `+` buttons for **R, G, B** fur colour (live swatch and a preview monkey)
  - On-screen keyboard for your **name** and the host **IP**. Tap the NAME or IP field to choose
    which one you're typing into.
  - **HOST**, **JOIN**, **LEAVE**, **ENTER BACKROOMS**
- **Backrooms map**: a seeded procedural yellow maze (same layout for every player), flickering lights,
  and a **BACK TO LOBBY** panel on the wall where you spawn.
- **Multiplayer**: Godot ENet on port 7777. One headset hosts, the others join by IP on the same
  Wi-Fi network. Pose, colour, name and voice are relayed through the host.
- **Talking eyes**: when someone talks, their monkey's eyes grow big. Every other monkey's pupils
  follow the current speaker. The preview monkey in the lobby does the same for you.
- **Voice chat**: simple 8-bit 16 kHz mic audio sent to everyone, played from each monkey's head.

## Build the APK

Requirements: Godot **4.3 or newer** (4.4 recommended), JDK 17, Android SDK / command-line tools
(see Godot docs: "Exporting for Android"), a Quest with **Developer Mode** on.

1. Open this folder in Godot (`project.godot`).
2. **AssetLib** -> search **"Godot OpenXR Vendors"** -> Download -> Install. Then
   *Project -> Project Settings -> Plugins* and enable it.
3. *Project -> Install Android Build Template...* (Gradle build is required for Quest).
4. *Project -> Export -> Add... -> Android*, then set:
   - **Use Gradle Build**: on
   - **XR Mode**: OpenXR
   - **Architectures**: arm64-v8a only
   - **Meta Quest** (Godot OpenXR Vendors) plugin: on, supported devices Quest 2/3/Pro
   - **Permissions**: *Record Audio* and *Internet* on
   - Package name: e.g. `com.yourname.monkeybackrooms`
5. Set up a debug or release keystore in Editor Settings / the export preset.
6. **Export Project** to get a `.apk` (or use *One-Click Deploy* with the Quest connected by USB).
7. Install manually with `adb install monkeybackrooms.apk`, or with SideQuest. It appears under
   **Unknown Sources** in your Quest library.

## Playing together

1. Everyone: open the app, stand at the lobby computer, set a name and colour.
2. One player presses **HOST**. The status line shows the host's Wi-Fi IP.
3. The others tap the IP field, type the IP with the on-screen keyboard (digits and `.`), then **JOIN**.
4. Everyone presses **ENTER BACKROOMS**. Talk to see the eye effects.

Headsets must be on the same network, and the host's router must not block device-to-device traffic
(guest Wi-Fi often does). For play over the internet the host needs UDP port 7777 forwarded.

## Notes / limitations

- I wrote this without being able to run Godot or a headset in my workspace, so it has **not been
  test-run**. Expect to fix a few small errors on first launch. Open the Output panel in Godot
  and send me anything that shows up.
- Voice chat is basic (low quality, no echo cancel). The Quest's own party chat works fine alongside
  it if you prefer.
- Movement can be intense; take breaks if you feel motion sick. Snap turn is on the right stick.
- The first time you run it, Godot may generate `openxr_action_map.tres`. Leave it as the default.

## Build the APK from your phone (GitHub Actions)

No computer needed. GitHub builds it for you in the cloud (free account is enough).

1. On github.com (phone browser, "Desktop site" helps) create a new repository.
2. Upload every file from this project, **including the hidden `.github` folder** (the file
   `.github/workflows/build.yml` must end up in the repo). Easiest way: unzip the project in your
   Files app and use *Add file -> Upload files*, or create `build.yml` by hand via
   *Add file -> Create new file* and paste its contents.
3. Open the **Actions** tab -> **Build Quest APK** -> **Run workflow**.
4. Wait about 5-10 minutes. Open the finished run and download **monkey-backrooms-apk**
   at the bottom (it's a zip containing the `.apk`).
5. Install it on the Quest with SideQuest (or `adb install` from a computer).

The workflow downloads Godot 4.3, its export templates and the Godot OpenXR Vendors plugin,
then exports a debug-signed APK using `export_presets.cfg`.

This setup is untested. If the run fails, open the failed step, copy the red error text, and send
it to me.
