class_name UltraHUD
extends CanvasLayer

## Broadcast HUD, menu, pause and end screens for ULTRABLADE. Built entirely in code.

signal start_requested
signal resume_requested
signal restart_requested
signal quit_requested
signal volume_changed(channel: String, value: float)
signal team_cycle_requested(side: String)

const CYAN := Color("21e6ff")
const MAGENTA := Color("ff2d6f")
const AMBER := Color("ffb020")
const BONE := Color("eaf6ff")
const STEEL := Color("6b839e")
const VOID := Color("05070f")
const BLUE := Color("0b67ff")
const FONT_BOLD_PATH := "res://assets/fonts/Rajdhani-Bold.ttf"
const FONT_SEMI_PATH := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const FONT_MONO_PATH := "res://assets/fonts/ShareTechMono-Regular.ttf"

var main: Node
var font_bold: FontFile
var font_semi: FontFile
var font_mono: FontFile

var app: Control
var hud_root: Control
var menu_root: Control
var pause_root: Control
var end_root: Control
var reticle: Reticle
var minimap: Minimap
var score_panel: ScorePanel
var cls_label: Label
var score_blue_label: Label
var score_red_label: Label
var clock_label: Label
var period_label: Label
var blue_name_label: Label
var red_name_label: Label
var home_team_name := "ICE SAINTS"
var away_team_name := "REDLINE SYNDICATE"
var home_team_color := CYAN
var away_team_color := MAGENTA
var _home_team_btn: Button
var _away_team_btn: Button
var player_name_label: Label
var player_role_label: Label
var hp_bar: StatBar
var boost_bar: StatBar
var hp_label: Label
var boost_label: Label
var prompt_label: Label
var rokV_label: Label
var state_label: Label
var announce_label: Label
var announce_sub_label: Label
var announce_tween: Tween
var goal_label: Label
var goal_sub_label: Label
var goal_panel: Control
var goal_tween: Tween
var kill_feed: VBoxContainer
var feed_entries: Array = []
var blue_pips: Array = []
var red_pips: Array = []
var volume_sliders: Dictionary = {}
var volume_value_labels: Dictionary = {}
var mute_status_label: Label
var menu_controls_panel: Panel
var _flash: ColorRect
var _vignette: Vignette
var _elapsed := 0.0
var _menu_mode := "main"
var _score_flash := 0.0
var _goal_side := 0

class Vignette extends Control:
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw() -> void:
        var vp := size
        # Corner darkening with cheap gradient strips.
        for i in range(18):
            var a := 0.055 * (1.0 - float(i) / 18.0)
            draw_rect(Rect2(0, vp.y * float(i) / 18.0, vp.x, vp.y / 18.0 + 1.0), Color(0, 0, 0, a * 0.25))
            draw_rect(Rect2(0, vp.y - vp.y * (float(i) + 1.0) / 18.0, vp.x, vp.y / 18.0 + 1.0), Color(0, 0, 0, a * 0.55))
        var scan := Color(0.35, 0.8, 1.0, 0.018)
        var y := 0.0
        while y < vp.y:
            draw_line(Vector2(0, y), Vector2(vp.x, y), scan, 1.0)
            y += 4.0

class MenuBackdrop extends Control:
    var t := 0.0
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _process(delta: float) -> void:
        t += delta
        queue_redraw()
    func _draw() -> void:
        var s := size
        # left-side opaque command deck, right side stays open to the drome
        var left_w := s.x * 0.47
        for i in range(48):
            var a := 0.02 + 0.012 * float(i) / 48.0
            draw_rect(Rect2(0, s.y * float(i) / 48.0, left_w, s.y / 48.0 + 1.0), Color(0.01, 0.02, 0.04, a))
        draw_rect(Rect2(0, 0, left_w, s.y), Color(0.01, 0.018, 0.035, 0.66))
        # diagonal chrome cut
        var pts := PackedVector2Array([Vector2(left_w, 0), Vector2(left_w + 90, 0), Vector2(left_w - 180, s.y), Vector2(left_w - 250, s.y)])
        draw_colored_polygon(pts, Color(0.01, 0.02, 0.04, 0.5))
        draw_line(Vector2(left_w + 90, 0), Vector2(left_w - 180, s.y), Color(CYAN.r, CYAN.g, CYAN.b, 0.2), 1.0)
        # faint vertical telemetry grid
        var x := 48.0
        while x < left_w:
            draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0.3, 0.6, 0.9, 0.035), 1.0)
            x += 80.0
        # moving scan band
        var by := fmod(t * 35.0, s.y + 220.0) - 110.0
        draw_rect(Rect2(0, by, left_w, 48), Color(CYAN.r, CYAN.g, CYAN.b, 0.018))
        # lower ticker line
        draw_line(Vector2(0, s.y - 88), Vector2(s.x, s.y - 88), Color(CYAN.r, CYAN.g, CYAN.b, 0.14), 1.0)
        draw_rect(Rect2(0, s.y - 88, s.x * 0.18, 2), Color(CYAN.r, CYAN.g, CYAN.b, 0.55))

class ScorePanel extends Control:
    var hud: UltraHUD
    var home_color := Color("21e6ff")
    var away_color := Color("ff2d6f")
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw() -> void:
        var s := size
        var w := s.x
        var h := s.y
        draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 18, h), Vector2(18, h)]), Color(0.015, 0.03, 0.055, 0.93))
        draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5 - 52, 0), Vector2(w * 0.5 - 66, h), Vector2(0, h)]), Color(home_color.r, home_color.g, home_color.b, 0.20))
        draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 + 66, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.5 + 52, h)]), Color(away_color.r, away_color.g, away_color.b, 0.18))
        draw_line(Vector2(18, h - 1), Vector2(w - 18, h - 1), Color(home_color.r, home_color.g, home_color.b, 0.55), 1.0)
        draw_line(Vector2(18, 1), Vector2(w - 18, 1), Color(1, 1, 1, 0.08), 1.0)
        # center notch
        draw_rect(Rect2(w * 0.5 - 54, 0, 1, h), Color(1, 1, 1, 0.1))
        draw_rect(Rect2(w * 0.5 + 53, 0, 1, h), Color(1, 1, 1, 0.1))
        draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 54, 0), Vector2(w * 0.5 + 54, 0), Vector2(w * 0.5 + 48, h), Vector2(w * 0.5 - 48, h)]), Color(0.01, 0.02, 0.04, 0.9))

class StatBar extends Control:
    var value := 1.0
    var color := Color.CYAN
    var bg := Color(0.02, 0.05, 0.08, 0.9)
    var segments := 12
    var horizontal := true
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw() -> void:
        var s := size
        draw_rect(Rect2(Vector2.ZERO, s), bg)
        var gap := 3.0
        var total_gap := gap * float(segments - 1)
        if horizontal:
            var seg_w := (s.x - total_gap) / float(segments)
            for i in range(segments):
                var active := (float(i) + 1.0) / float(segments) <= value + 0.001
                var c := color if active else Color(0.18, 0.25, 0.32, 0.18)
                draw_rect(Rect2(i * (seg_w + gap), 0, seg_w, s.y), c)
        else:
            var seg_h := (s.y - total_gap) / float(segments)
            for i in range(segments):
                var active := (float(i) + 1.0) / float(segments) <= value + 0.001
                var c := color if active else Color(0.18, 0.25, 0.32, 0.18)
                draw_rect(Rect2(0, s.y - (i + 1) * seg_h - i * gap, s.x, seg_h), c)

class Minimap extends Control:
    var hud: UltraHUD
    var home_color := Color("21e6ff")
    var away_color := Color("ff2d6f")
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw() -> void:
        var s := size
        var c := s * 0.5
        var rx := s.x * 0.47
        var ry := s.y * 0.46
        var pts := PackedVector2Array()
        for i in range(64):
            var a := TAU * float(i) / 64.0
            pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
        draw_colored_polygon(pts, Color(0.01, 0.04, 0.07, 0.78))
        var outline := PackedVector2Array(pts)
        outline.append(pts[0])
        draw_polyline(outline, Color(home_color.r, home_color.g, home_color.b, 0.5), 1.0)
        # center line + circles
        draw_line(Vector2(c.x, c.y - ry), Vector2(c.x, c.y + ry), Color(1, 1, 1, 0.14), 1.0)
        draw_arc(c + Vector2(0, ry * 0.58), 24.0, 0, TAU, 32, Color(1, 1, 1, 0.10), 1.0)
        draw_arc(c - Vector2(0, ry * 0.58), 24.0, 0, TAU, 32, Color(1, 1, 1, 0.10), 1.0)
        draw_arc(c, 18.0, 0, TAU, 32, Color(CYAN.r, CYAN.g, CYAN.b, 0.22), 1.0)
        if hud == null or hud.main == null:
            return
        var m = hud.main
        var bounds = m.get_drome_bounds() if m.has_method("get_drome_bounds") else {}
        var hw: float = bounds.get("half_width", 16.0)
        var hl: float = bounds.get("half_length", 31.0)
        # goals
        draw_rect(Rect2(c.x - 18, 2, 36, 5), Color(home_color.r, home_color.g, home_color.b, 0.9))
        draw_rect(Rect2(c.x - 18, s.y - 7, 36, 5), Color(away_color.r, away_color.g, away_color.b, 0.9))
        var puck = m.get_puck()
        if puck != null:
            var p := _world_to_map(puck.global_position, c, rx, ry, hw, hl)
            draw_circle(p, 3.2, AMBER if puck.charged else Color.WHITE)
        var skaters: Array = m.get_skaters()
        for sk in skaters:
            if sk == null or sk.downed:
                continue
            var p := _world_to_map(sk.global_position, c, rx, ry, hw, hl)
            var col: Color = sk.team_color
            if sk == m.get_controlled_skater():
                draw_arc(p, 6.0, 0, TAU, 18, Color(1, 1, 1, 0.9), 1.5)
            draw_circle(p, 3.5, col)
        # goal flashes
        if m.score_blue > 0:
            draw_circle(Vector2(c.x, s.y - 4), 2.0, Color(1, 1, 1, 0.4))
    func _world_to_map(p: Vector3, c: Vector2, rx: float, ry: float, hw: float, hl: float) -> Vector2:
        var u := clampf(p.x / hw, -1.0, 1.0)
        var v := clampf(p.z / hl, -1.0, 1.0)
        # note: +z is red end at bottom; draw blue goal at top
        return c + Vector2(u * rx, v * ry)

class Reticle extends Control:
    var hud: UltraHUD
    func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw() -> void:
        if hud == null or hud.main == null:
            return
        var c := size * 0.5
        var st = hud.main.get_state_name() if hud.main.has_method("get_state_name") else "menu"
        if st != "playing" and st != "countdown":
            return
        var charge := 0.0
        var carrying := false
        var sk = hud.main.get_controlled_skater()
        if sk != null:
            charge = sk.shoot_charge if sk.charging else 0.0
            carrying = sk.carrying
        var col := AMBER if charge > 0.0 else CYAN
        var gap := 8.0 + charge * -3.0
        var length := 9.0
        draw_line(c + Vector2(0, -gap - length), c + Vector2(0, -gap), col, 1.5)
        draw_line(c + Vector2(0, gap), c + Vector2(0, gap + length), col, 1.5)
        draw_line(c + Vector2(-gap - length, 0), c + Vector2(-gap, 0), col, 1.5)
        draw_line(c + Vector2(gap, 0), c + Vector2(gap + length, 0), col, 1.5)
        draw_circle(c, 1.6, col)
        if charge > 0.0:
            draw_arc(c, 28.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 42, col, 3.0)
            draw_arc(c, 34.0, 0, TAU, 42, Color(col.r, col.g, col.b, 0.18), 1.0)
        if carrying:
            draw_arc(c, 48.0, 0, TAU, 48, Color(CYAN.r, CYAN.g, CYAN.b, 0.2), 1.0)

func setup(p_main: Node) -> void:
    main = p_main
    layer = 10
    font_bold = load(FONT_BOLD_PATH)
    font_semi = load(FONT_SEMI_PATH)
    font_mono = load(FONT_MONO_PATH)
    if font_bold == null:
        font_bold = ThemeDB.fallback_font
    if font_semi == null:
        font_semi = font_bold
    if font_mono == null:
        font_mono = font_bold
    _build()

func _build() -> void:
    app = Control.new()
    app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    app.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(app)

    _vignette = Vignette.new()
    _vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    app.add_child(_vignette)

    hud_root = Control.new()
    hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    app.add_child(hud_root)

    # score panel
    score_panel = ScorePanel.new()
    score_panel.hud = self
    score_panel.anchor_left = 0.5
    score_panel.anchor_right = 0.5
    score_panel.offset_left = -310
    score_panel.offset_right = 310
    score_panel.offset_top = 26
    score_panel.offset_bottom = 122
    hud_root.add_child(score_panel)
    blue_name_label = _label(hud_root, "ICE SAINTS", 16, CYAN, Vector2(524, 32), Vector2(180, 22), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    red_name_label = _label(hud_root, "REDLINE SYNDICATE", 16, MAGENTA, Vector2(896, 32), Vector2(180, 22), HORIZONTAL_ALIGNMENT_RIGHT, font_bold)
    score_blue_label = _label(hud_root, "0", 50, BONE, Vector2(570, 48), Vector2(80, 62), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    score_red_label = _label(hud_root, "0", 50, BONE, Vector2(950, 48), Vector2(80, 62), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    clock_label = _label(hud_root, "01:30", 30, BONE, Vector2(740, 44), Vector2(120, 40), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    period_label = _label(hud_root, "P1", 13, STEEL, Vector2(760, 82), Vector2(80, 18), HORIZONTAL_ALIGNMENT_CENTER, font_semi)
    cls_label = _label(hud_root, "DROME LEAGUE // EXHIBITION", 11, Color(STEEL.r, STEEL.g, STEEL.b, 0.8), Vector2(600, 7), Vector2(400, 18), HORIZONTAL_ALIGNMENT_CENTER, font_mono)

    # roster / pips
    _build_roster_pips()

    # player status
    player_name_label = _label(hud_root, "KAI VOSS", 26, BONE, Vector2(42, 626), Vector2(380, 34), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    player_role_label = _label(hud_root, "STRIKER // ICE SAINTS", 12, CYAN, Vector2(44, 660), Vector2(320, 18), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(hud_root, "INTEGRITY", 10, STEEL, Vector2(44, 690), Vector2(120, 16), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    hp_bar = StatBar.new()
    hp_bar.anchor_top = 1.0
    hp_bar.anchor_bottom = 1.0
    hp_bar.offset_left = 44
    hp_bar.offset_top = -188
    hp_bar.offset_right = 404
    hp_bar.offset_bottom = -176
    hud_root.add_child(hp_bar)
    hp_label = _label(hud_root, "100", 13, BONE, Vector2(340, 686), Vector2(64, 18), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)
    _label(hud_root, "BOOST", 10, STEEL, Vector2(44, 748), Vector2(100, 16), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    boost_bar = StatBar.new()
    boost_bar.anchor_top = 1.0
    boost_bar.anchor_bottom = 1.0
    boost_bar.offset_left = 44
    boost_bar.offset_top = -130
    boost_bar.offset_right = 404
    boost_bar.offset_bottom = -124
    boost_bar.color = CYAN
    boost_bar.segments = 20
    hud_root.add_child(boost_bar)
    boost_label = _label(hud_root, "READY", 12, CYAN, Vector2(340, 744), Vector2(64, 18), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)
    rokV_label = _label(hud_root, "ROK // LOOSE", 12, STEEL, Vector2(44, 784), Vector2(360, 20), HORIZONTAL_ALIGNMENT_LEFT, font_mono)

    # reticle
    reticle = Reticle.new()
    reticle.hud = self
    reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud_root.add_child(reticle)

    # minimap
    minimap = Minimap.new()
    minimap.hud = self
    minimap.anchor_left = 1.0
    minimap.anchor_top = 1.0
    minimap.anchor_right = 1.0
    minimap.anchor_bottom = 1.0
    minimap.offset_left = -338
    minimap.offset_top = -268
    minimap.offset_right = -42
    minimap.offset_bottom = -48
    hud_root.add_child(minimap)
    _label(hud_root, "DRONE FEED", 10, Color(CYAN.r, CYAN.g, CYAN.b, 0.7), Vector2(1290, 640), Vector2(200, 16), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)

    # prompt + state
    prompt_label = _label(hud_root, "", 18, BONE, Vector2(500, 782), Vector2(600, 28), HORIZONTAL_ALIGNMENT_CENTER, font_semi)
    state_label = _label(hud_root, "", 12, Color(CYAN.r, CYAN.g, CYAN.b, 0.8), Vector2(500, 810), Vector2(600, 18), HORIZONTAL_ALIGNMENT_CENTER, font_mono)

    # kill feed
    kill_feed = VBoxContainer.new()
    kill_feed.anchor_left = 1.0
    kill_feed.anchor_right = 1.0
    kill_feed.offset_left = -560
    kill_feed.offset_right = -42
    kill_feed.offset_top = 148
    kill_feed.offset_bottom = 380
    kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
    kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud_root.add_child(kill_feed)

    # center announcement
    announce_label = _label(hud_root, "", 52, BONE, Vector2(300, 320), Vector2(1000, 66), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    announce_sub_label = _label(hud_root, "", 16, CYAN, Vector2(300, 386), Vector2(1000, 28), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    announce_label.modulate.a = 0.0
    announce_sub_label.modulate.a = 0.0

    _build_goal_overlay()
    _build_menu()
    _build_pause()
    _build_end()

    _flash = ColorRect.new()
    _flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _flash.color = Color(1, 1, 1, 0)
    _flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    app.add_child(_flash)

func _build_roster_pips() -> void:
    var blue_x := 42.0
    var red_x := 1558.0
    for i in range(2):
        var b := StatBar.new()
        b.horizontal = false
        b.segments = 5
        b.color = CYAN
        b.anchor_left = 0.0
        b.anchor_top = 0.0
        b.offset_left = blue_x + i * 18.0
        b.offset_top = 44
        b.offset_right = blue_x + i * 18.0 + 10
        b.offset_bottom = 94
        hud_root.add_child(b)
        blue_pips.append(b)
        var r := StatBar.new()
        r.horizontal = false
        r.segments = 5
        r.color = MAGENTA
        r.anchor_left = 1.0
        r.anchor_top = 0.0
        r.offset_left = -red_x + i * 18.0 + red_x - 52
        r.offset_top = 44
        r.offset_right = -red_x + i * 18.0 + red_x - 42
        r.offset_bottom = 94
        hud_root.add_child(r)
        red_pips.append(r)

func _build_goal_overlay() -> void:
    goal_panel = Control.new()
    goal_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    goal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    goal_panel.modulate.a = 0.0
    hud_root.add_child(goal_panel)
    var band := ColorRect.new()
    band.color = Color(0.01, 0.02, 0.04, 0.72)
    band.anchor_left = 0.0
    band.anchor_right = 1.0
    band.anchor_top = 0.5
    band.anchor_bottom = 0.5
    band.offset_top = -78
    band.offset_bottom = 78
    band.mouse_filter = Control.MOUSE_FILTER_IGNORE
    goal_panel.add_child(band)
    goal_label = _label(goal_panel, "GOAL", 118, BONE, Vector2(0, 338), Vector2(1600, 140), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    goal_sub_label = _label(goal_panel, "ICE SAINTS", 22, CYAN, Vector2(0, 478), Vector2(1600, 30), HORIZONTAL_ALIGNMENT_CENTER, font_mono)

func _on_home_team_pressed() -> void:
    team_cycle_requested.emit("home")

func _on_away_team_pressed() -> void:
    team_cycle_requested.emit("away")

func _build_menu() -> void:
    menu_root = Control.new()
    menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
    app.add_child(menu_root)
    var bg := MenuBackdrop.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_root.add_child(bg)
    _label(menu_root, "DROME LEAGUE  //  SEASON 09", 13, Color(CYAN.r, CYAN.g, CYAN.b, 0.8), Vector2(72, 62), Vector2(600, 22), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(menu_root, "LIVE BLOODSPORT FEED", 11, Color(1, 0.3, 0.4, 0.75), Vector2(72, 88), Vector2(400, 18), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(menu_root, "U L T R A", 22, CYAN, Vector2(76, 250), Vector2(600, 34), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    _label(menu_root, "BLADE", 168, BONE, Vector2(62, 266), Vector2(660, 160), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    _label(menu_root, "THE DROME REMEMBERS", 22, Color(CYAN.r, CYAN.g, CYAN.b, 0.92), Vector2(76, 438), Vector2(600, 30), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(menu_root, "A modern remake of the 1996 future-sport classic.\nTwo forwards. One rok. No rules worth keeping.", 17, Color(0.66, 0.78, 0.9, 0.78), Vector2(76, 488), Vector2(570, 64), HORIZONTAL_ALIGNMENT_LEFT, font_semi)
    var team_panel := Panel.new()
    team_panel.position = Vector2(940, 370)
    team_panel.size = Vector2(390, 152)
    var team_style := StyleBoxFlat.new()
    team_style.bg_color = Color(0.008, 0.02, 0.035, 0.82)
    team_style.border_color = Color(STEEL.r, STEEL.g, STEEL.b, 0.3)
    team_style.border_width_left = 1
    team_style.border_width_top = 1
    team_style.border_width_right = 1
    team_style.border_width_bottom = 1
    team_style.corner_radius_top_left = 2
    team_style.corner_radius_top_right = 2
    team_panel.add_theme_stylebox_override("panel", team_style)
    menu_root.add_child(team_panel)
    _label(menu_root, "TEAM SELECT  //  EXHIBITION", 12, Color(STEEL.r, STEEL.g, STEEL.b, 0.85), Vector2(956, 388), Vector2(420, 20), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _home_team_btn = _menu_button(menu_root, "HOME // " + home_team_name, Vector2(956, 414), Vector2(340, 36), false)
    _home_team_btn.pressed.connect(_on_home_team_pressed)
    _away_team_btn = _menu_button(menu_root, "AWAY // " + away_team_name, Vector2(956, 456), Vector2(340, 36), false)
    _away_team_btn.pressed.connect(_on_away_team_pressed)
    _label(menu_root, "CLICK TO ROTATE SQUAD", 10, Color(STEEL.r, STEEL.g, STEEL.b, 0.6), Vector2(956, 496), Vector2(360, 16), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    var start_btn := _menu_button(menu_root, "ENTER THE DROME", Vector2(76, 590), Vector2(400, 58), true)
    start_btn.pressed.connect(func(): start_requested.emit())
    var controls_btn := _menu_button(menu_root, "CONTROLS // FIELD MANUAL", Vector2(76, 660), Vector2(400, 44), false)
    controls_btn.pressed.connect(_toggle_controls.bind(controls_btn))
    var quit_btn := _menu_button(menu_root, "LEAVE THE DROME", Vector2(76, 716), Vector2(400, 40), false)
    quit_btn.pressed.connect(func(): quit_requested.emit())
    _label(menu_root, "ENTER  //  START", 12, Color(STEEL.r, STEEL.g, STEEL.b, 0.9), Vector2(960, 826), Vector2(600, 18), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)
    _label(menu_root, "A NON-COMMERCIAL HOMAGE TO HYPERBLADE (1996)", 10, Color(STEEL.r, STEEL.g, STEEL.b, 0.6), Vector2(76, 840), Vector2(700, 18), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(menu_root, "BUILD 0.2 // GODOT 4.7.2 // PC", 10, Color(STEEL.r, STEEL.g, STEEL.b, 0.6), Vector2(960, 852), Vector2(600, 18), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)
    # controls card
    menu_controls_panel = Panel.new()
    menu_controls_panel.anchor_left = 1.0
    menu_controls_panel.anchor_right = 1.0
    menu_controls_panel.anchor_top = 1.0
    menu_controls_panel.anchor_bottom = 1.0
    menu_controls_panel.offset_left = -610
    menu_controls_panel.offset_right = -52
    menu_controls_panel.offset_top = -332
    menu_controls_panel.offset_bottom = -92
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.01, 0.025, 0.045, 0.9)
    sb.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.35)
    sb.border_width_left = 1
    sb.border_width_top = 1
    sb.border_width_right = 1
    sb.border_width_bottom = 1
    sb.corner_radius_top_left = 2
    sb.corner_radius_top_right = 2
    menu_controls_panel.add_theme_stylebox_override("panel", sb)
    menu_root.add_child(menu_controls_panel)
    _label(menu_controls_panel, "FIELD MANUAL", 14, CYAN, Vector2(24, 18), Vector2(300, 20), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    _label(menu_controls_panel, "WASD  skate      MOUSE  look / aim\nLMB   slash / hold to charge shot\nRMB   heavy slash       SHIFT  boost\nSPACE jump             E  pass\nQ     throw killball    ESC  pause\nM mute       [ / ]  master volume", 15, Color(0.68, 0.8, 0.92, 0.92), Vector2(24, 56), Vector2(500, 170), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(menu_controls_panel, "SCORE. DISMANTLE. REPEAT.", 11, Color(AMBER.r, AMBER.g, AMBER.b, 0.8), Vector2(24, 212), Vector2(500, 18), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    menu_controls_panel.visible = false

func _build_pause() -> void:
    pause_root = Control.new()
    pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
    app.add_child(pause_root)
    var dark := ColorRect.new()
    dark.color = Color(0.005, 0.01, 0.02, 0.84)
    dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    pause_root.add_child(dark)
    _label(pause_root, "FEED PAUSED", 16, CYAN, Vector2(0, 220), Vector2(1600, 24), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    _label(pause_root, "HOLD.", 112, BONE, Vector2(0, 240), Vector2(1600, 130), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    _label(pause_root, "The drome can wait. The crowd cannot.", 18, Color(STEEL.r, STEEL.g, STEEL.b, 0.9), Vector2(0, 378), Vector2(1600, 26), HORIZONTAL_ALIGNMENT_CENTER, font_semi)
    var resume := _menu_button(pause_root, "RESUME FEED", Vector2(600, 470), Vector2(400, 54), true)
    resume.pressed.connect(func(): resume_requested.emit())
    var restart := _menu_button(pause_root, "RESTART MATCH", Vector2(600, 538), Vector2(400, 42), false)
    restart.pressed.connect(func(): restart_requested.emit())
    var quit := _menu_button(pause_root, "LEAVE DROME", Vector2(600, 596), Vector2(400, 38), false)
    quit.pressed.connect(func(): quit_requested.emit())
    _build_audio_panel()
    _label(pause_root, "ESC  //  RESUME   [ ]  MASTER   M  MUTE", 12, Color(STEEL.r, STEEL.g, STEEL.b, 0.7), Vector2(0, 828), Vector2(1600, 18), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    pause_root.visible = false

func _build_audio_panel() -> void:
    var panel := Panel.new()
    panel.position = Vector2(570, 650)
    panel.size = Vector2(460, 158)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.008, 0.022, 0.04, 0.92)
    style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.24)
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    panel.add_theme_stylebox_override("panel", style)
    pause_root.add_child(panel)
    _label(panel, "AUDIO MIX", 14, CYAN, Vector2(18, 10), Vector2(200, 20), HORIZONTAL_ALIGNMENT_LEFT, font_bold)
    var rows := [["MASTER", 38], ["MUSIC", 72], ["SFX", 106]]
    for row in rows:
        var channel := String(row[0]).to_lower()
        var y := int(row[1])
        _label(panel, String(row[0]), 11, STEEL, Vector2(18, y), Vector2(80, 22), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
        var slider := HSlider.new()
        slider.position = Vector2(100, y + 2)
        slider.size = Vector2(270, 20)
        slider.min_value = 0.0
        slider.max_value = 100.0
        slider.step = 1.0
        slider.value = 100.0
        slider.focus_mode = Control.FOCUS_NONE
        var track := StyleBoxFlat.new()
        track.bg_color = Color(0.04, 0.09, 0.14, 0.95)
        track.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.25)
        track.border_width_top = 1
        track.border_width_bottom = 1
        var fill := StyleBoxFlat.new()
        fill.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.58)
        var fill_hi := fill.duplicate() as StyleBoxFlat
        fill_hi.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.9)
        slider.add_theme_stylebox_override("slider", track)
        slider.add_theme_stylebox_override("grabber_area", fill)
        slider.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
        var value_label := _label(panel, "100%", 11, BONE, Vector2(378, y), Vector2(60, 22), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)
        slider.value_changed.connect(_on_volume_slider.bind(channel, value_label))
        panel.add_child(slider)
        volume_sliders[channel] = slider
        volume_value_labels[channel] = value_label
    mute_status_label = _label(panel, "M  //  MUTE", 10, STEEL, Vector2(18, 134), Vector2(300, 16), HORIZONTAL_ALIGNMENT_LEFT, font_mono)
    _label(panel, "[  ]  MASTER", 10, Color(STEEL.r, STEEL.g, STEEL.b, 0.8), Vector2(300, 134), Vector2(140, 16), HORIZONTAL_ALIGNMENT_RIGHT, font_mono)

func _on_volume_slider(value: float, channel: String, value_label: Label) -> void:
    if value_label:
        value_label.text = str(int(round(value))) + "%"
    volume_changed.emit(channel, value / 100.0)

func set_audio_settings(master: float, music: float, sfx: float, muted: bool) -> void:
    var values := {"master": master, "music": music, "sfx": sfx}
    for channel in values.keys():
        var slider = volume_sliders.get(channel)
        if slider != null:
            slider.set_value_no_signal(clampf(float(values[channel]) * 100.0, 0.0, 100.0))
        var value_label = volume_value_labels.get(channel)
        if value_label != null:
            value_label.text = str(int(round(clampf(float(values[channel]), 0.0, 1.0) * 100.0))) + "%"
    if mute_status_label != null:
        mute_status_label.text = "MUTED  //  PRESS M" if muted else "M  //  MUTE"
        mute_status_label.add_theme_color_override("font_color", AMBER if muted else STEEL)


func _build_end() -> void:
    end_root = Control.new()
    end_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    end_root.mouse_filter = Control.MOUSE_FILTER_STOP
    app.add_child(end_root)
    var dark := ColorRect.new()
    dark.color = Color(0.005, 0.01, 0.02, 0.88)
    dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    end_root.add_child(dark)
    var end_title := _label(end_root, "VICTORY", 102, CYAN, Vector2(0, 238), Vector2(1600, 120), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    end_title.name = "EndTitle"
    var end_sub := _label(end_root, "ICE SAINTS TAKE THE DROME", 20, BONE, Vector2(0, 366), Vector2(1600, 28), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    end_sub.name = "EndSub"
    var end_score := _label(end_root, "0  —  0", 62, BONE, Vector2(0, 420), Vector2(1600, 80), HORIZONTAL_ALIGNMENT_CENTER, font_bold)
    end_score.name = "EndScore"
    var rematch := _menu_button(end_root, "REMATCH", Vector2(600, 552), Vector2(400, 54), true)
    rematch.pressed.connect(func(): restart_requested.emit())
    var menu := _menu_button(end_root, "RETURN TO LOCKER", Vector2(600, 618), Vector2(400, 40), false)
    menu.pressed.connect(func(): quit_requested.emit())
    _label(end_root, "R  //  REMATCH", 12, Color(STEEL.r, STEEL.g, STEEL.b, 0.7), Vector2(0, 830), Vector2(1600, 18), HORIZONTAL_ALIGNMENT_CENTER, font_mono)
    end_root.visible = false

func _menu_button(parent: Control, text: String, pos: Vector2, sz: Vector2, primary: bool) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = sz
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.add_theme_font_override("font", font_bold)
    b.add_theme_font_size_override("font_size", 20 if primary else 15)
    b.add_theme_color_override("font_color", BONE if primary else Color(0.6, 0.72, 0.84))
    b.add_theme_color_override("font_hover_color", Color.WHITE)
    b.add_theme_color_override("font_pressed_color", Color.WHITE)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.15) if primary else Color(0.01, 0.03, 0.05, 0.5)
    normal.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.8) if primary else Color(0.3, 0.45, 0.6, 0.35)
    normal.border_width_left = 2 if primary else 1
    normal.border_width_top = 1
    normal.border_width_right = 1
    normal.border_width_bottom = 1
    normal.corner_radius_top_left = 2
    normal.corner_radius_top_right = 2
    normal.content_margin_left = 22
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.28) if primary else Color(CYAN.r, CYAN.g, CYAN.b, 0.12)
    hover.border_color = CYAN
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.4)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", hover)
    b.add_theme_stylebox_override("pressed", pressed)
    b.add_theme_stylebox_override("focus", hover)
    parent.add_child(b)
    return b

func _toggle_controls(btn: Button) -> void:
    menu_controls_panel.visible = not menu_controls_panel.visible
    btn.text = "CLOSE FIELD MANUAL" if menu_controls_panel.visible else "CONTROLS // FIELD MANUAL"

func _label(parent: Control, text: String, font_size: int, color: Color, pos: Vector2, sz: Vector2, align: int, font: Font) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.size = sz
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", font)
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(l)
    return l

func set_team_identity(home_name: String, home_color: Color, away_name: String, away_color: Color) -> void:
    home_team_name = home_name
    away_team_name = away_name
    home_team_color = home_color
    away_team_color = away_color
    if blue_name_label:
        blue_name_label.text = home_name
        blue_name_label.add_theme_color_override("font_color", home_color)
    if red_name_label:
        red_name_label.text = away_name
        red_name_label.add_theme_color_override("font_color", away_color)
    if score_panel:
        score_panel.home_color = home_color
        score_panel.away_color = away_color
        score_panel.queue_redraw()
    if minimap:
        minimap.home_color = home_color
        minimap.away_color = away_color
        minimap.queue_redraw()
    if _home_team_btn:
        _home_team_btn.text = "HOME // " + home_name
        _home_team_btn.add_theme_color_override("font_color", home_color)
    if _away_team_btn:
        _away_team_btn.text = "AWAY // " + away_name
        _away_team_btn.add_theme_color_override("font_color", away_color)
    if main and main.has_method("get_controlled_skater"):
        _update_player_status()

func show_menu() -> void:
    menu_root.visible = true
    hud_root.visible = false
    pause_root.visible = false
    end_root.visible = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_menu() -> void:
    menu_root.visible = false
    hud_root.visible = true

func set_hud_visible(v: bool) -> void:
    hud_root.visible = v

func show_pause(v: bool) -> void:
    pause_root.visible = v
    hud_root.visible = not v
    if v:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        if DisplayServer.get_name() != "headless":
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_paused(v: bool) -> void:
    show_pause(v)

func show_end(victory: bool, score_text: String, subtitle: String) -> void:
    end_root.visible = true
    hud_root.visible = false
    var t := end_root.find_child("EndTitle", true, false) as Label
    var s := end_root.find_child("EndScore", true, false) as Label
    var sub := end_root.find_child("EndSub", true, false) as Label
    if t:
        t.text = "VICTORY" if victory else "DEFEAT"
        t.add_theme_color_override("font_color", CYAN if victory else MAGENTA)
    if s:
        s.text = score_text
    if sub:
        sub.text = subtitle
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_end() -> void:
    end_root.visible = false

func show_goal(team: int, scorer: String) -> void:
    _goal_side = team
    if announce_tween:
        announce_tween.kill()
    announce_label.modulate.a = 0.0
    announce_sub_label.modulate.a = 0.0
    goal_panel.modulate.a = 1.0
    var col := home_team_color if team == 0 else away_team_color
    goal_label.text = "GOAL"
    goal_label.add_theme_color_override("font_color", BONE)
    goal_sub_label.text = (home_team_name if team == 0 else away_team_name) + "  //  " + scorer
    goal_sub_label.add_theme_color_override("font_color", col)
    if goal_tween:
        goal_tween.kill()
    goal_panel.scale = Vector2(1.08, 1.08)
    goal_panel.pivot_offset = Vector2(800, 450)
    goal_tween = create_tween()
    goal_tween.set_parallel(true)
    goal_tween.tween_property(goal_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    goal_tween.tween_property(goal_panel, "modulate:a", 0.0, 0.5).set_delay(1.35)
    _score_flash = 0.25

func announce(text: String, sub: String = "", color: Color = BONE, duration: float = 2.0) -> void:
    if announce_tween:
        announce_tween.kill()
    announce_label.text = text
    announce_sub_label.text = sub
    announce_label.add_theme_color_override("font_color", color)
    announce_label.modulate.a = 0.0
    announce_sub_label.modulate.a = 0.0
    announce_tween = create_tween()
    announce_tween.set_parallel(true)
    announce_tween.tween_property(announce_label, "modulate:a", 1.0, 0.18)
    announce_tween.tween_property(announce_sub_label, "modulate:a", 1.0, 0.18)
    announce_tween.chain().tween_interval(duration)
    announce_tween.chain().tween_property(announce_label, "modulate:a", 0.0, 0.35)
    announce_tween.parallel().tween_property(announce_sub_label, "modulate:a", 0.0, 0.35)

func add_kill_feed(text: String, color: Color = BONE) -> void:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    l.add_theme_font_override("font", font_mono)
    l.add_theme_font_size_override("font_size", 15)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 1)
    kill_feed.add_child(l)
    feed_entries.append({"node": l, "time": 5.0})
    if feed_entries.size() > 5:
        var old = feed_entries.pop_front()
        if is_instance_valid(old.node):
            old.node.queue_free()

func screen_flash(color: Color, strength: float = 0.25) -> void:
    _flash.color = Color(color.r, color.g, color.b, strength)
    var tw := create_tween()
    tw.tween_property(_flash, "color:a", 0.0, 0.25)

func set_announcements_visible(v: bool) -> void:
    announce_label.visible = v
    announce_sub_label.visible = v

func set_goal_visible(v: bool) -> void:
    goal_panel.visible = v

func _process(delta: float) -> void:
    _elapsed += delta
    if main == null:
        return
    _update_feed(delta)
    if _score_flash > 0.0:
        _score_flash = maxf(0.0, _score_flash - delta)
    minimap.queue_redraw()
    reticle.queue_redraw()
    if not hud_root.visible:
        return
    _update_score()
    _update_player_status()
    _update_prompt()

func _update_score() -> void:
    score_blue_label.text = str(main.get_team_score(0))
    score_red_label.text = str(main.get_team_score(1))
    var clock: float = main.get_match_clock()
    var mins := int(clock) / 60
    var secs := int(clock) % 60
    clock_label.text = "%02d:%02d" % [mins, secs]
    period_label.text = "P%d" % clampi(main.get_period(), 1, 9)
    cls_label.text = "DROME LEAGUE // " + ("OVERTIME" if main.is_overtime() else "EXHIBITION")
    if _score_flash > 0.0:
        var a := _score_flash * 4.0
        score_blue_label.modulate = Color(1, 1, 1, 1).lerp(home_team_color, a)
        score_red_label.modulate = Color(1, 1, 1, 1).lerp(away_team_color, a)
    else:
        score_blue_label.modulate = Color.WHITE
        score_red_label.modulate = Color.WHITE

func _update_player_status() -> void:
    var sk = main.get_controlled_skater()
    if sk == null:
        player_name_label.text = "SPECTATOR"
        player_role_label.text = "NO ACTIVE FORWARD"
        hp_bar.value = 0.0
        boost_bar.value = 0.0
        hp_label.text = "--"
        boost_label.text = "--"
        rokV_label.text = "ALL FORWARDS DOWN // RESERVE PENDING"
        return
    player_name_label.text = sk.display_name
    player_role_label.text = sk.get_role_name().to_upper() + " // " + (home_team_name if sk.team_id == 0 else away_team_name)
    player_role_label.add_theme_color_override("font_color", home_team_color if sk.team_id == 0 else away_team_color)
    hp_bar.value = sk.hp / 100.0
    hp_bar.color = home_team_color if sk.hp > 35.0 else MAGENTA
    hp_label.text = str(int(ceil(sk.hp)))
    boost_bar.value = sk.stamina / 100.0
    boost_bar.color = AMBER if sk.stamina < 22.0 else CYAN
    boost_label.text = "CHARGING" if sk.stamina < 100.0 and sk.want_boost else str(int(sk.stamina)) + "%"
    var puck = main.get_puck()
    if sk.carrying:
        if puck and puck.charged:
            rokV_label.text = "ROK // KILLBALL ARMED"
            rokV_label.add_theme_color_override("font_color", AMBER)
        else:
            rokV_label.text = "ROK // POSSESSION"
            rokV_label.add_theme_color_override("font_color", CYAN)
    elif puck != null and puck.carrier != null:
        rokV_label.text = "ROK // TAKEN BY " + puck.carrier.display_name
        rokV_label.add_theme_color_override("font_color", MAGENTA)
    else:
        rokV_label.text = "ROK // LOOSE"
        rokV_label.add_theme_color_override("font_color", STEEL)

func _update_prompt() -> void:
    var sk = main.get_controlled_skater()
    var st: String = main.get_state_name()
    if st == "countdown":
        prompt_label.text = ""
        state_label.text = "FEED LIVE // FACE OFF"
        return
    if st == "goal":
        prompt_label.text = ""
        state_label.text = ""
        return
    if st == "period_break":
        prompt_label.text = "PERIOD BREAK"
        state_label.text = "RESERVES RESET // ICE CREW DEPLOYED"
        return
    if sk == null:
        prompt_label.text = "RESERVES INBOUND"
        state_label.text = "SPECTATING // NEXT STOPPAGE"
        return
    var puck = main.get_puck()
    if sk.carrying:
        if puck and puck.charged:
            prompt_label.text = "KILLBALL ARMED  //  Q  THROW AT TARGET  //  HOLD LMB  SHOOT"
            state_label.text = "LETHAL PROJECTILE READY"
        elif sk.charging:
            prompt_label.text = "RELEASE LMB  //  FIRE ON " + ("+Z" if sk.team_id == 0 else "-Z") + " GOAL"
            state_label.text = "SHOT CHARGE %d%%" % int(sk.shoot_charge * 100.0)
        else:
            prompt_label.text = "HOLD LMB  CHARGE SHOT   //   E  PASS   //   SHIFT  BOOST"
            state_label.text = "ROK SECURED"
    else:
        prompt_label.text = "TAKE THE ROK  //  RMB  SLASH   //   SHIFT  BOOST   //   SPACE  JUMP"
        state_label.text = "PUCK LOOSE // CLOSE FOR POSSESSION"
    if main.has_method("get_context_hint"):
        var hint: String = main.get_context_hint()
        if hint != "":
            prompt_label.text = hint

func _update_feed(delta: float) -> void:
    var remove: Array = []
    for e in feed_entries:
        e.time -= delta
        if e.time < 0.8 and is_instance_valid(e.node):
            e.node.modulate.a = maxf(0.0, e.time / 0.8)
        if e.time <= 0.0:
            remove.append(e)
            if is_instance_valid(e.node):
                e.node.queue_free()
    for r in remove:
        feed_entries.erase(r)

func set_prompt(text: String) -> void:
    prompt_label.text = text
