# Claude Sounds — Community Packs

Share your sound packs with the community!

## Using community packs

Community packs appear automatically in the **Sound Packs** browser under the "Available" section. Just open the app, browse, and click **Download & Install**.

You can also install any pack directly via **Install URL...** using the zip link from the table below.

## Available packs

| Pack | Author | Description | Download |
|------|--------|-------------|----------|
| StarCraft Protoss | Blizzard Entertainment | Protoss voice lines from StarCraft | [protoss.zip](https://github.com/michalarent/claude-sounds/releases/download/v2.0/protoss.zip) |
| Super Mario Bros. (NES) | Community | Classic NES sound effects from Super Mario Bros. | [super-mario-nes.zip](https://github.com/michalarent/claude-sounds/releases/download/v2.0/super-mario-nes.zip) |
| Diablo II Necromancer | Community | Necromancer voice lines and spell sounds from Diablo II | [diablo-2-necromancer.zip](https://github.com/michalarent/claude-sounds/releases/download/v2.0/diablo-2-necromancer.zip) |
| Cuphead Announcer | Community | Announcer voice lines from Cuphead: Don't Deal With the Devil! | [cuphead-announcer.zip](https://github.com/michalarent/claude-sounds/releases/download/v2.0/cuphead-announcer.zip) |

## Contributing a pack

### Pack structure

Your zip must contain a single folder named after your pack ID, with subfolders for each event:

```
my-pack/
  session-start/
    sound1.wav
    sound2.wav
  prompt-submit/
    sound1.wav
  notification/
    sound1.wav
  stop/
    sound1.wav
  session-end/
    sound1.wav
  subagent-stop/     (optional)
  tool-failure/      (optional)
```

### Requirements

- **Pack ID**: lowercase, hyphens only (e.g. `office-sounds`, `lotr-quotes`)
- **Audio formats**: `.wav`, `.mp3`, `.aiff`, `.m4a`, `.ogg`, `.aac`
- **Clip length**: Keep clips short — ideally under 2 seconds, max 5 seconds
- **Zip layout**: The zip extracts a single directory named `<pack-id>/`
- **No copyrighted material** you don't have rights to distribute

### How to submit

**Option A: From the app** (easiest)

1. Create or edit a pack locally using the Sound Editor
2. Click **Publish...** (in the Sound Editor or Pack Browser)
3. Fill in the metadata and click **Submit to Community...**
4. The app forks the repo, updates the manifest, and opens a PR automatically

**Option B: Manually**

1. Fork this repo
2. Upload your zip to a GitHub Release on your fork (or any publicly accessible URL)
3. Update `community/manifest.json` — add an entry to the `packs` array:
   ```json
   {
     "id": "my-pack",
     "name": "My Sound Pack",
     "description": "Short description of your pack",
     "version": "1.0",
     "author": "Your Name",
     "download_url": "https://github.com/<your-user>/claude-sounds/releases/download/v1.0/my-pack.zip",
     "size": "1.2 MB",
     "file_count": 15,
     "preview_url": null
   }
   ```
4. Open a PR (only the manifest change — no zip files in the repo)

Once merged, CI validates the pack (magic bytes, structure, no symlinks/path traversal) and re-hosts your zip under the official releases. Your pack will appear in the Sound Pack Browser for all users.
