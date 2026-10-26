extends SceneTree

## Headless inspector for imported ActionForge GLBs.

func _init() -> void:
    var rig_path := "res://assets/actionforge/rig/rig-human.glb"
    var packed: PackedScene = load(rig_path)
    if packed == null:
        print("RIG_LOAD_FAIL")
        quit(1)
        return
    var n := packed.instantiate()
    print("=== RIG TREE ===")
    _dump(n, 0)
    var ap := n.find_child("AnimationPlayer", true, false)
    print("animation_player=", ap != null)
    if ap:
        print("anims=", ap.get_animation_list())
    var skel := n.find_child("Skeleton3D", true, false)
    print("skeleton=", skel != null)
    if skel:
        print("bones=", skel.get_bone_count())
        for i in range(min(skel.get_bone_count(), 8)):
            print("  ", i, " ", skel.get_bone_name(i), " parent=", skel.get_bone_parent(i))
    n.free()

    print("=== ANIM CLIPS ===")
    var dir := DirAccess.open("res://assets/actionforge/animations")
    var names: PackedStringArray = dir.get_files()
    for f in names:
        if not f.ends_with(".glb"):
            continue
        var ps: PackedScene = load("res://assets/actionforge/animations/" + f)
        if ps == null:
            print(f, " LOAD_FAIL")
            continue
        var inst := ps.instantiate()
        var ap2 := inst.find_child("AnimationPlayer", true, false)
        print(f, " root=", inst.name, " ap=", ap2 != null)
        if ap2:
            print("  anims=", ap2.get_animation_list())
            for a in ap2.get_animation_list():
                var anim = ap2.get_animation(a)
                print("  ", a, " len=", anim.length, " tracks=", anim.get_track_count())
                if anim.get_track_count() > 0:
                    print("    track0=", anim.track_get_path(0))
        inst.free()

    quit(0)

func _dump(n: Node, depth: int) -> void:
    print("  ".repeat(depth), n.name, " <", n.get_class(), ">")
    for c in n.get_children():
        _dump(c, depth + 1)
