extends SceneTree

## Windowed proof for the pause-screen audio mix. Saves artifacts/captures/05-pause.png.
## Run: godot --path game -s res://tools/volume_preview.gd

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    var main = packed.instantiate()
    root.add_child(main)
    for i in range(6):
        await process_frame
    main.pause_match()
    for i in range(3):
        await process_frame
    var original_master: float = main.master_volume
    var original_music: float = main.music_volume
    var original_sfx: float = main.sfx_volume
    var original_muted: bool = main.audio_muted
    main.hud.volume_sliders["master"].value = 65.0
    main.hud.volume_sliders["music"].value = 50.0
    main.hud.volume_sliders["sfx"].value = 80.0
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    var dir := ProjectSettings.globalize_path("res://") + "../artifacts/captures"
    DirAccess.make_dir_recursive_absolute(dir)
    var path := dir + "/05-pause.png"
    var err := img.save_png(path)
    print("VOLUME_PREVIEW_CAPTURE path=", path, " err=", err, " master=", main.hud.volume_sliders["master"].value)
    # Restore the user's real settings so a preview capture never changes their mix.
    main._on_volume_changed("master", original_master)
    main._on_volume_changed("music", original_music)
    main._on_volume_changed("sfx", original_sfx)
    main.audio_muted = original_muted
    main._apply_audio_settings()
    main._save_audio_settings()
    main._sync_hud_audio()
    if main.audio != null:
        main.audio.free()
        main.audio = null
        for i in range(3):
            await process_frame
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    main.queue_free()
    for i in range(3):
        await process_frame
    quit(0)
