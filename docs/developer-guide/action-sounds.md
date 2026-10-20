# Action sounds

`ActionClick.caf` and `ActionDrop.caf` in `Sources/OpenClip/Resources/Sounds/` are derived from Pixabay sounds
(`app_interface_click_2` and `ui-pop-sound`), licensed under the Pixabay Content License. They are trimmed,
converted to mono 16-bit 44.1 kHz, normalized and faded out, so they differ from the originals.

A custom sound is chosen with the folder button in Settings → General. The file is copied to
`~/.openclip/sounds/custom.<ext>`, so it survives the original being moved. It must decode in Core Audio (WAV, AIFF,
CAF, MP3, M4A, AAC, FLAC), be at most 5 seconds and 5 MB; `CustomActionSound` enforces this.

A custom sound is chosen with "Choose File…" at the bottom of the sound dropdown in Settings → General. The file is
copied to `~/.openclip/sounds/custom.<ext>`, so it survives the original being moved. It must decode in Core Audio
(WAV, AIFF, CAF, MP3, M4A, AAC, FLAC) and be at most 5 seconds and 5 MB; `CustomActionSound` enforces this.
