# Claude Sounds — Community Packs

Share your sound packs with the community!

## Using community packs

Community packs appear automatically in the **Sound Packs** browser under the "Available" section. Just open the app, browse, and click **Download & Install**.

You can also install any pack directly via **Install URL...** using the zip link from the table below.

## Available packs

| Pack | Author | Description | Download |
|------|--------|-------------|----------|
| Super Mario Bros. (NES) | Community | Classic NES sound effects from Super Mario Bros. | [super-mario-nes.zip](packs/super-mario-nes.zip) |

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

1. Fork this repo
2. Add your zip to `community/packs/<pack-id>.zip`
3. Update `community/manifest.json` — add an entry to the `packs` array:
   ```json
   {
     "id": "my-pack",
     "name": "My Sound Pack",
     "description": "Short description of your pack",
     "version": "1.0",
     "author": "Your Name",
     "download_url": "https://raw.githubusercontent.com/michalarent/claude-sounds/main/community/packs/my-pack.zip",
     "size": "1.2 MB",
     "file_count": 15,
     "preview_url": null
   }
   ```
4. Open a PR

That's it! Once merged, anyone with the community registry will see your pack.
