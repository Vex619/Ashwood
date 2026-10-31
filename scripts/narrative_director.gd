class_name NarrativeDirector
extends Node3D
## Phase 3 Master Narrative, Monster, Hazard & RTX Volumetric Director for "SILENT WEIGHT".
##
## Orchestrates:
##   1. Dual-Tier Graphics Scaler (F4 Toggle: RTX ULTRA vs iGPU LIGHT) hooked into
##      WorldEnvironment, volumetric SpotLight3D/OmniLight3D, FogVolume, GPUParticles3D,
##      and the F3 PerfHudOverlay.
##   2. Zone-Gated Processing (Area3D gates for Act I, Act II, Act III) so off-screen
##      monsters, hazards, and particle emitters consume 0 CPU/GPU cycles.
##   3. Checkpoint & 1.2s Fade-to-Black Soft-Respawn Manager.
##   4. Act I ("The Silent Bunker"): Blind Auditor Ceiling-Rail Acoustic Drones,
##      2.4m HardLand Acoustic Bait, Counterweight Lever, and Crushing Steel Sluice Gate.
##   5. Act II ("What Lurks in the Mud"): Low-lying FogVolume, Mire Stalker with
##      real-time Reactive Swamp Shader ripples & Wetness Carry-Over detection,
##      High-Pressure Steam Pistons (3.5s cycle + acoustic masking), and 220 kg
##      Emergency Beacon Crate (3.8m warm amber volumetric repulsion halo).
##   6. Act III ("The Harvester's Field"): Towering Harvester Titan silhouette,
##      7.0s Gale Shockwaves (2.5s horn telegraph + crate shadow shelter check),
##      12-degree Climax Slope (60% -> 95% -> 100% Strain Factor ramp), Hound Pursuer,
##      Counterweight Cradle Crush Sacrifice, Vertical Volumetric Rescue Beacon, and
##      ultra-wide catharsis ending title.

const ACTION_TOGGLE_GRAPHICS: StringName = &"toggle_graphics_preset"

const PRESET_RTX_ULTRA: String = "[RTX ULTRA: Volumetrics + SSR + SSAO ON]"
const PRESET_IGPU_LIGHT: String = "[iGPU LIGHT: Fake Light Planes Only]"

@export var player: PlayerController3D
@export var camera_rig: DynamicCameraRig3D
@export var foley_director: FoleyAudioDirector3D
@export var perf_hud: PerfHudOverlay
@export var world_environment: WorldEnvironment
@export var beacon_crate: RigidBody3D

# Graphics & Environment State ----------------------------------------------
var _rtx_ultra_enabled: bool = true
var _directional_light: DirectionalLight3D = null
var _volumetric_lights: Array[Light3D] = []
var _act1_lights: Array[Light3D] = []
var _act2_lights: Array[Light3D] = []
var _act3_lights: Array[Light3D] = []
var _fake_shafts: Array[MeshInstance3D] = []
var _fog_volumes: Array[FogVolume] = []
var _act1_particles: Array[GPUParticles3D] = []
var _act2_particles: Array[GPUParticles3D] = []
var _act3_particles: Array[GPUParticles3D] = []

# Zone Gating State ---------------------------------------------------------
var _active_act: int = 1
var _act1_root: Node3D = null
var _act2_root: Node3D = null
var _act3_root: Node3D = null
var _base_zone1: Node3D = null
var _base_zone2: Node3D = null
var _base_zone3: Node3D = null

# Checkpoint & Soft-Respawn State -------------------------------------------
var _checkpoints: Array[Vector3] = [
	Vector3(-19.0, 0.5, 0.0),   # CP 0: Act I Waking in Bunker (0.5m above Y=0.0)
	Vector3(-3.2, 2.9, 0.0),    # CP 1: Act I 2.4m Ledge Bait & Sluice Gate (0.5m above Y=2.4)
	Vector3(73.0, 0.5, 0.0),    # CP 2: Act II Swamp Entry & Ripple Chase (0.5m above Y=0.0)
	Vector3(106.0, 1.25, 0.0),  # CP 3: Act II Steam Piston Catwalk (0.5m above Y=0.75)
	Vector3(143.0, 1.25, 0.0),  # CP 4: Act II 220 kg Beacon Crate Pier (0.5m above Y=0.75)
	Vector3(187.5, 0.5, 0.0),   # CP 5: Act III Windy Field & Harvester Shockwaves (0.5m above Y=0.0)
	Vector3(252.0, 0.5, 0.0),   # CP 6: Act III Climax Slope & Final Sacrifice (0.5m above Y=0.0)
]
var _crate_checkpoints: Array[Vector3] = [
	Vector3(145.5, 1.5, 0.0),
	Vector3(145.5, 1.5, 0.0),
	Vector3(145.5, 1.5, 0.0),
	Vector3(145.5, 1.5, 0.0),
	Vector3(145.5, 1.5, 0.0),
	Vector3(190.5, 1.0, 0.0),
	Vector3(254.5, 1.0, 0.0),
]
var _current_cp_index: int = 0
var _respawning: bool = false
var _respawn_timer: float = 0.0
var _respawn_duration: float = 1.2
var _respawn_teleported: bool = false
var _respawn_stage: int = 0
var _cam_saved_fov: float = 52.0
var _quote_bag: Array[int] = []
var _fade_rect: ColorRect = null
var _death_panel: Control = null
var _death_header_label: Label = null
var _death_quote_label: Label = null
var _death_footer_label: Label = null
var _title_panel: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null

const DEATH_QUOTES: Array[String] = [
	# Iconic Gaming Characters (Dark Souls, Bloodborne, Max Payne, Planescape: Torment, Silent Hill, Nier: Automata, Disco Elysium, Metal Gear Solid, BioShock)
	"\"Don't you dare go Hollow.\"\n— Laurentius of the Great Swamp, Dark Souls",
	"\"Be safe, friend. Don't you dare go Hollow.\"\n— Laurentius of the Great Swamp, Dark Souls",
	"\"Men are props on the stage of life, and no matter how tender, how exquisite... a lie will remain a lie.\"\n— Aldia, Scholar of the First Sin, Dark Souls II",
	"\"There is no path. Beyond the scope of light, beyond the reach of Dark... what could possibly await us?\"\n— Aldia, Scholar of the First Sin, Dark Souls II",
	"\"Seek strength. The rest will follow.\"\n— King Vendrick, Dark Souls II",
	"\"Fret not, father, we have no need of thy flail. Tis only the flame, quivering at misguided Ash.\"\n— Sister Friede, Dark Souls III",
	"\"Fear not the dark, my friend, and let the feast begin.\"\n— Locust Preacher, Dark Souls III",
	"\"Hand it over. That thing, your dark soul.\"\n— Slave Knight Gael, Dark Souls III",
	"\"Thou'rt Ash, and fire befits thee, of course.\"\n— Fire Keeper, Dark Souls III",
	"\"Every age, it seems, is tainted by the greed of men.\"\n— Oswald of Carim, Dark Souls",
	"\"A corpse... should be left well alone.\"\n— Lady Maria of the Astral Clocktower, Bloodborne",
	"\"Tonight, Gehrman joins the hunt.\"\n— Gehrman, the First Hunter, Bloodborne",
	"\"The night, and the dream, were long.\"\n— Gehrman, the First Hunter, Bloodborne",
	"\"We are born of the blood, made men by the blood, undone by the blood.\"\n— Master Willem, Bloodborne",
	"\"A hunter is a hunter, even in a dream.\"\n— Micolash, Host of the Nightmare, Bloodborne",
	"\"Curse the fiends, their children too. And their children, forever true.\"\n— Banished Villager, Bloodborne",
	"\"Nightmarish rituals crave a newborn. Find one, and silence its harrowing cry.\"\n— Note in Yahar'gul, Bloodborne",
	"\"Death is inevitable. Our fear of it makes us play safe, blocks out emotion. It's a losing game.\"\n— Max Payne, Max Payne 2",
	"\"The past is a puzzle, like a broken mirror. As you piece it together, you cut yourself.\"\n— Max Payne, Max Payne 2",
	"\"They were all dead. The final gunshot was an exclamation mark to everything that had led to this point.\"\n— Max Payne, Max Payne",
	"\"In the land of the blind, the one-eyed man is king.\"\n— Max Payne, Max Payne",
	"\"You'll walk—with a limp—but you'll walk.\"\n— Mona Sax, Max Payne 2",
	"\"Nothing stops the night from coming.\"\n— Max Payne, Max Payne 3",
	"\"What can change the nature of a man?\"\n— Ravel Puzzlewell, Planescape: Torment",
	"\"Time is not your enemy. Forever is.\"\n— Fall-From-Grace, Planescape: Torment",
	"\"Endure. In enduring, grow strong.\"\n— Dak'kon, Planescape: Torment",
	"\"When a mind does not know itself, it is flawed. When a mind is flawed, the man is flawed.\"\n— Dak'kon, Planescape: Torment",
	"\"Regret is the heaviest stone a mortal carries to the grave.\"\n— The Nameless One, Planescape: Torment",
	"\"In my restless dreams, I see that town.\"\n— Mary Shepherd-Sunderland, Silent Hill 2",
	"\"It's hot as hell in here. For me, it's always like this.\"\n— Angela Orosco, Silent Hill 2",
	"\"Monsters? They look like monsters to you?\"\n— Vincent Smith, Silent Hill 3",
	"\"There was a hole here. It's gone now.\"\n— Neely's Bar Message, Silent Hill 2",
	"\"Everything that lives is designed to end. We are perpetually trapped in a never-ending spiral of life and death.\"\n— 2B, NieR: Automata",
	"\"Is this a curse? Or some kind of punishment?\"\n— 2B, NieR: Automata",
	"\"A future is not given to you. It is something you must take for yourself.\"\n— Pod 042, NieR: Automata",
	"\"To be alive is to be continuously broken and remade in silence.\"\n— 9S, NieR: Automata",
	"\"In the dark times, should the stars also go out?\"\n— Steban, Disco Elysium",
	"\"Nooster's Law: Every man carries his own ruin inside his coat pocket.\"\n— Ancient Reptilian Brain, Disco Elysium",
	"\"There is nothing. Only warm, primordial blackness. Your conscience ferments in it.\"\n— Ancient Reptilian Brain, Disco Elysium",
	"\"Subdue the regret. Dust yourself off, proceed. You'll get it in the next life, where you don't make mistakes.\"\n— Volition, Disco Elysium",
	"\"The road to healing is going to be a long one. Stay the course.\"\n— Volition, Disco Elysium",
	"\"Un jour je serai de retour près de toi.\"\n— Cindy the SKULL, Disco Elysium",
	"\"Why are we still here? Just to suffer? Every night, I can feel my leg... and my arm...\"\n— Kazuhira Miller, Metal Gear Solid V",
	"\"A strong man doesn't need to read the future. He makes his own.\"\n— Solid Snake, Metal Gear Solid",
	"\"There's only room for one Boss and one Snake.\"\n— The Boss, Metal Gear Solid 3",
	"\"We're not tools of the government, or anyone else. Fighting was the only thing I was good at.\"\n— Gray Fox, Metal Gear Solid",
	"\"We all make choices, but in the end our choices make us.\"\n— Andrew Ryan, BioShock",
	"\"Lives, lived, will live. Dies, died, will die.\"\n— Robert Lutece, BioShock Infinite",
	"\"There's always a lighthouse. There's always a man. There's always a city.\"\n— Elizabeth, BioShock Infinite",

	# Cinema (Blade Runner, The Seventh Seal, No Country for Old Men, Apocalypse Now, Stalker)
	"\"All those moments will be lost in time, like tears in rain. Time to die.\"\n— Roy Batty, Blade Runner (1982)",
	"\"Quite an experience to live in fear, isn't it? That's what it is to be a slave.\"\n— Roy Batty, Blade Runner (1982)",
	"\"The light that burns twice as bright burns half as long.\"\n— Eldon Tyrell, Blade Runner (1982)",
	"\"I have seen things you people wouldn't believe.\"\n— Roy Batty, Blade Runner (1982)",
	"\"Who are you?\" — \"I am Death.\" — \"Have you come for me?\" — \"I have been walking by your side for a long time.\"\n— Antonius Block & Death, The Seventh Seal (1957)",
	"\"My flesh is afraid, creating ghosts in the dark. But I am not afraid.\"\n— Antonius Block, The Seventh Seal (1957)",
	"\"Nothing escapes me. No one escapes me.\"\n— Death, The Seventh Seal (1957)",
	"\"I want knowledge! Not faith, not assumptions, but knowledge. I want God to stretch out His hand and speak to me.\"\n— Antonius Block, The Seventh Seal (1957)",
	"\"You can't stop what's coming. It ain't all waiting on you. That's vanity.\"\n— Ellis, No Country for Old Men (2007)",
	"\"If the rule you followed brought you to this, of what use was the rule?\"\n— Anton Chigurh, No Country for Old Men (2007)",
	"\"Somewhere out there is a true and living prophet of destruction and I don't want to confront him.\"\n— Sheriff Ed Tom Bell, No Country for Old Men (2007)",
	"\"The horror... the horror.\"\n— Colonel Walter E. Kurtz, Apocalypse Now (1979)",
	"\"You have a right to kill me, you have a right to do that, but you have no right to judge me.\"\n— Colonel Walter E. Kurtz, Apocalypse Now (1979)",
	"\"Weakness is a great thing, and strength is nothing. When a man is just born, he is weak and flexible. When he dies, he is hard and insensitive.\"\n— The Stalker, Stalker (1979)",
	"\"Let everything that's been planned come true. Let them believe. And let them have a laugh at their passions.\"\n— The Stalker, Stalker (1979)",

	# Philosophers & Writers (Seneca, Marcus Aurelius, Schopenhauer, Nietzsche, Camus, Kafka, Cioran, Dostoevsky, Sartre)
	"\"We suffer more often in imagination than in reality.\"\n— Seneca, Letters from a Stoic",
	"\"We are dying every day; for every day some part of our life is taken from us.\"\n— Seneca, Epistulae Morales",
	"\"He who fears death will never do anything worthy of a man who is alive.\"\n— Seneca, On Tranquillity of Mind",
	"\"Sometimes even to live is an act of courage.\"\n— Seneca, Letters from a Stoic",
	"\"No man is more unhappy than he who never faces adversity.\"\n— Seneca, On Providence",
	"\"It is not death that a man should fear, but he should fear never beginning to live.\"\n— Marcus Aurelius, Meditations",
	"\"You could leave life right now. Let that determine what you do and say and think.\"\n— Marcus Aurelius, Meditations",
	"\"How ridiculous and how strange to be surprised at anything which happens in life.\"\n— Marcus Aurelius, Meditations",
	"\"Soon you will have forgotten everything; soon everybody will have forgotten you.\"\n— Marcus Aurelius, Meditations",
	"\"Think of yourself as dead. You have lived your life. Now, take what's left and live it properly.\"\n— Marcus Aurelius, Meditations",
	"\"Life is a constant process of dying.\"\n— Arthur Schopenhauer, Studies in Pessimism",
	"\"After your death you will be what you were before your birth.\"\n— Arthur Schopenhauer, Parerga and Paralipomena",
	"\"Each day is a little life: every waking and rising a little birth, every fresh morning a little youth, every going to rest and sleep a little death.\"\n— Arthur Schopenhauer, Counsels and Maxims",
	"\"Man can do what he wills, but he cannot will what he wills.\"\n— Arthur Schopenhauer, On the Freedom of the Will",
	"\"Whoever fights monsters should see to it that in the process he does not become a monster. And if you gaze long enough into an abyss, the abyss will gaze back into you.\"\n— Friedrich Nietzsche, Beyond Good and Evil",
	"\"He who has a why to live for can bear almost any how.\"\n— Friedrich Nietzsche, Twilight of the Idols",
	"\"To live is to suffer, to survive is to find some meaning in the suffering.\"\n— Friedrich Nietzsche",
	"\"That which does not kill us makes us stronger.\"\n— Friedrich Nietzsche, Twilight of the Idols",
	"\"Many die too late, and a few die too early.\"\n— Friedrich Nietzsche, Thus Spoke Zarathustra",
	"\"The struggle itself toward the heights is enough to fill a man's heart. One must imagine Sisyphus happy.\"\n— Albert Camus, The Myth of Sisyphus",
	"\"There is but one truly serious philosophical problem, and that is suicide.\"\n— Albert Camus, The Myth of Sisyphus",
	"\"In the depth of winter, I finally learned that within me there lay an invincible summer.\"\n— Albert Camus, Return to Tipasa",
	"\"The absurd is born of this confrontation between the human need and the unreasonable silence of the world.\"\n— Albert Camus, The Myth of Sisyphus",
	"\"A cage went in search of a bird.\"\n— Franz Kafka, The Zürau Aphorisms",
	"\"There is an infinite amount of hope in the universe... but not for us.\"\n— Franz Kafka, Conversations with Kafka",
	"\"From a certain point onward there is no longer any turning back. That is the point that must be reached.\"\n— Franz Kafka, The Trial",
	"\"The meaning of life is that it stops.\"\n— Franz Kafka, Diaries",
	"\"It is not worth the bother of killing yourself, since you always kill yourself too late.\"\n— Emil Cioran, The Trouble with Being Born",
	"\"Without the idea of suicide, I would have surely killed myself.\"\n— Emil Cioran, All Gall Is Divided",
	"\"Consciousness is much more than the thorn, it is the dagger in the flesh.\"\n— Emil Cioran, The Fall into Time",
	"\"Only optimists commit suicide, optimists who no longer succeed at being optimists.\"\n— Emil Cioran, A Short History of Decay",
	"\"Pain and suffering are always inevitable for a large intelligence and a deep heart.\"\n— Fyodor Dostoevsky, Crime and Punishment",
	"\"Above all, don't lie to yourself. The man who lies to himself and listens to his own lie comes to a point that he cannot distinguish the truth within him.\"\n— Fyodor Dostoevsky, The Brothers Karamazov",
	"\"Man is a mystery. It needs to be unravelled, and if you spend your whole life unravelling it, don't say that you've wasted time.\"\n— Fyodor Dostoevsky, Letters",
	"\"Man is condemned to be free; because once thrown into the world, he is responsible for everything he does.\"\n— Jean-Paul Sartre, Existentialism Is a Humanism",
	"\"Every existing thing is born without reason, prolongs itself out of weakness, and dies by chance.\"\n— Jean-Paul Sartre, Nausea",

	# Scientists & Thinkers (Oppenheimer, Feynman, Sagan, Einstein, Bohr)
	"\"Now I am become Death, the destroyer of worlds.\"\n— J. Robert Oppenheimer (quoting the Bhagavad Gita, 1945)",
	"\"We knew the world would not be the same. A few people laughed, a few people cried. Most people were silent.\"\n— J. Robert Oppenheimer",
	"\"I would rather have questions that can't be answered than answers that can't be questioned.\"\n— Richard P. Feynman",
	"\"Nobody ever figures out what life is all about, and it doesn't matter. Explore the world.\"\n— Richard P. Feynman",
	"\"You are under no obligation to remain the same person you were a year ago, a month ago, or even fifteen minutes ago.\"\n— Richard P. Feynman",
	"\"For small creatures such as we, the vastness is bearable only through love.\"\n— Carl Sagan, Contact",
	"\"Look again at that dot. That's here. That's home. That's us. On it everyone you love, everyone you know, everyone you ever heard of, lived out their lives.\"\n— Carl Sagan, Pale Blue Dot",
	"\"We are a way for the cosmos to know itself.\"\n— Carl Sagan, Cosmos",
]

# Act I: The Blind Auditor & Crushing Sluice Gate ---------------------------
var _auditor_1: AnimatableBody3D = null
var _auditor_1_light: SpotLight3D = null
var _auditor_1_audio: AudioStreamPlayer3D = null
var _auditor_1_buzz: AudioStreamPlayer3D = null
var _auditor_1_buzz_phase: float = 0.0
var _auditor_1_target_x: float = -10.5
var _auditor_1_alert_timer: float = 0.0
var _auditor_1_exposure: float = 0.0
var _sustained_run_timer: float = 0.0

var _auditor_2: AnimatableBody3D = null
var _auditor_2_light: SpotLight3D = null
var _auditor_2_audio: AudioStreamPlayer3D = null
var _auditor_2_buzz: AudioStreamPlayer3D = null
var _auditor_2_buzz_phase: float = 0.0
var _auditor_2_target_x: float = 34.0
var _auditor_2_alert_timer: float = 0.0
var _auditor_2_exposure: float = 0.0
var _auditor_2_baited_timer: float = 0.0

var _lever_pivot: Node3D = null
var _sluice_gate_1: AnimatableBody3D = null
var _sluice_sparks_1: GPUParticles3D = null
var _sluice_audio_1: AudioStreamPlayer3D = null
var _sluice_1_open_timer: float = 0.0
var _sluice_1_height: float = 0.95

# Act II: The Mire Stalker, Steam Pistons & 220 kg Beacon Crate -------------
var _mire_stalker: Node3D = null
var _mire_tendrils: Array[MeshInstance3D] = []
var _mire_splash_particles: GPUParticles3D = null
var _mire_audio: AudioStreamPlayer3D = null
var _mire_x: float = 92.0
var _mire_agitation: float = 0.0
var _mire_strike_exposure: float = 0.0
var _beacon_omni_light: OmniLight3D = null
var _crate_lifted_to_field: bool = false
var _crate_hoisting: bool = false
var _crate_hoist_timer: float = 0.0
var _crate_hoist_start: Vector3 = Vector3.ZERO
var _crate_hoist_target: Vector3 = Vector3(185.2, 2.02, 0.0)
var _crate_reached_marsh_exit: bool = false

var _piston_1_head: AnimatableBody3D = null
var _piston_2_head: AnimatableBody3D = null
var _piston_1_steam: GPUParticles3D = null
var _piston_2_steam: GPUParticles3D = null
var _piston_1_audio: AudioStreamPlayer3D = null
var _piston_2_audio: AudioStreamPlayer3D = null
var _piston_cycle_timer: float = 0.0
var _steam_mask_active: bool = false

# Act III: The Harvester Titan, Gale Shockwaves, Hound Pursuer & Climax -----
var _harvester_root: Node3D = null
var _harvester_legs: Array[Node3D] = []
var _harvester_spotlight: SpotLight3D = null
var _harvester_horn_audio: AudioStreamPlayer3D = null
var _shockwave_timer: float = 0.0
var _shockwave_cycle_sec: float = 7.0
var _shockwave_telegraph_sec: float = 2.5
var _shockwave_active_sec: float = 1.15
var _horn_played_this_cycle: bool = false
var _wind_rain_particles: GPUParticles3D = null
var _act3_grass_multimesh: MultiMeshInstance3D = null
var _act3_grass_material: ShaderMaterial = null
var _act3_gust_intensity: float = 0.0

var _hound_pursuer: Node3D = null
var _hound_light: SpotLight3D = null
var _hound_audio: AudioStreamPlayer3D = null
var _hound_active: bool = false
var _hound_crushed: bool = false
var _hound_x: float = 238.0

var _trapdoor_mesh: Node3D = null
var _rescue_beacon_light: SpotLight3D = null
var _rescue_beacon_shaft: MeshInstance3D = null
var _ending_triggered: bool = false
var _ending_timer: float = 0.0
var _ending_cam_region: CameraRegionVolume3D = null

# Shared Procedural Materials -----------------------------------------------
var _mat_silhouette_black: StandardMaterial3D = null
var _mat_concrete_dark: StandardMaterial3D = null
var _mat_metal_rust: StandardMaterial3D = null
var _mat_crimson_eye: StandardMaterial3D = null
var _mat_amber_beacon: StandardMaterial3D = null
var _mat_white_beacon: StandardMaterial3D = null
var _time_accum: float = 0.0


func _ready() -> void:
	_resolve_core_nodes()
	_ensure_f4_input()
	_build_shared_materials()
	_build_fade_and_title_overlay()
	_collect_existing_shafts()
	_assemble_three_act_world()
	_connect_player_signals()
	_apply_graphics_preset(true)
	_update_zone_gating(true)


func _exit_tree() -> void:
	_volumetric_lights.clear()
	_act1_lights.clear()
	_act2_lights.clear()
	_act3_lights.clear()
	_fake_shafts.clear()
	_fog_volumes.clear()
	_act1_particles.clear()
	_act2_particles.clear()
	_act3_particles.clear()
	_mire_tendrils.clear()
	_harvester_legs.clear()
	_act3_grass_multimesh = null
	_act3_grass_material = null
	_mat_silhouette_black = null
	_mat_concrete_dark = null
	_mat_metal_rust = null
	_mat_crimson_eye = null
	_mat_amber_beacon = null
	_mat_white_beacon = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE_GRAPHICS):
		_rtx_ultra_enabled = not _rtx_ultra_enabled
		_apply_graphics_preset(_rtx_ultra_enabled)
		get_viewport().set_input_as_handled()
		return

	if _respawning and _respawn_stage == 1 and _respawn_timer >= 1.35:
		var awaken_pressed: bool = event.is_action_pressed(&"ui_accept") or event.is_action_pressed(PlayerController3D.ACTION_JUMP)
		if not awaken_pressed and event is InputEventKey:
			var kev: InputEventKey = event as InputEventKey
			if kev.pressed and not kev.echo and (kev.physical_keycode == KEY_SPACE or kev.physical_keycode == KEY_ENTER or kev.physical_keycode == KEY_KP_ENTER or kev.keycode == KEY_SPACE or kev.keycode == KEY_ENTER):
				awaken_pressed = true
		if awaken_pressed:
			_begin_awaken_fade_out()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_time_accum += delta
	if _respawning:
		_process_respawn_fade(delta)
		return
	if player == null:
		return

	# Fail-Safe Abyss Respawn Guard
	if player.global_position.y < -5.5:
		player.velocity = Vector3.ZERO
		_trigger_capture("Abyss Guard", 0.0)
		return

	_update_checkpoints_and_zone()
	if _ending_triggered:
		_process_ending_sequence(delta)
		return

	match _active_act:
		1:
			_process_act1_bunker(delta)
		2:
			_process_act2_swamp(delta)
		3:
			_process_act3_field(delta)


# --------------------------------------------------------------------------
# Initialization & Node Resolution
# --------------------------------------------------------------------------

func _resolve_core_nodes() -> void:
	var root: Node = get_parent()
	if root == null:
		return
	if player == null:
		player = root.get_node_or_null(^"Player") as PlayerController3D
	if camera_rig == null:
		camera_rig = root.get_node_or_null(^"DynamicCameraRig3D") as DynamicCameraRig3D
	if foley_director == null:
		foley_director = root.get_node_or_null(^"FoleyAudioDirector3D") as FoleyAudioDirector3D
	if perf_hud == null:
		perf_hud = root.get_node_or_null(^"PerfHudOverlay") as PerfHudOverlay
	if world_environment == null:
		world_environment = root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if _directional_light == null:
		_directional_light = root.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	if beacon_crate == null:
		beacon_crate = root.get_node_or_null(^"Zone3_WindyField/HeavyPushableCrate") as RigidBody3D
	_base_zone1 = root.get_node_or_null(^"Zone1_ConcreteBunker") as Node3D
	_base_zone2 = root.get_node_or_null(^"Zone2_SwampMarsh") as Node3D
	_base_zone3 = root.get_node_or_null(^"Zone3_WindyField") as Node3D


func _ensure_f4_input() -> void:
	if not InputMap.has_action(ACTION_TOGGLE_GRAPHICS):
		InputMap.add_action(ACTION_TOGGLE_GRAPHICS)
	if InputMap.action_get_events(ACTION_TOGGLE_GRAPHICS).is_empty():
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_F4
		InputMap.action_add_event(ACTION_TOGGLE_GRAPHICS, ev)


func _connect_player_signals() -> void:
	if player == null:
		return
	if not player.kinetic_state_changed.is_connected(_on_player_kinetic_state_changed):
		player.kinetic_state_changed.connect(_on_player_kinetic_state_changed)
	if not player.stride_phase_triggered.is_connected(_on_player_stride_phase_triggered):
		player.stride_phase_triggered.connect(_on_player_stride_phase_triggered)


func _build_shared_materials() -> void:
	_mat_silhouette_black = StandardMaterial3D.new()
	_mat_silhouette_black.albedo_color = Color(0.02, 0.025, 0.03, 1.0)
	_mat_silhouette_black.roughness = 0.35
	_mat_silhouette_black.metallic = 0.65

	_mat_concrete_dark = StandardMaterial3D.new()
	_mat_concrete_dark.albedo_color = Color(0.20, 0.22, 0.25, 1.0)
	_mat_concrete_dark.roughness = 0.78

	_mat_metal_rust = StandardMaterial3D.new()
	_mat_metal_rust.albedo_color = Color(0.16, 0.13, 0.12, 1.0)
	_mat_metal_rust.roughness = 0.45
	_mat_metal_rust.metallic = 0.82

	_mat_crimson_eye = StandardMaterial3D.new()
	_mat_crimson_eye.albedo_color = Color(1.0, 0.12, 0.12, 1.0)
	_mat_crimson_eye.emission_enabled = true
	_mat_crimson_eye.emission = Color(1.0, 0.08, 0.08, 1.0)
	_mat_crimson_eye.emission_energy_multiplier = 4.5

	_mat_amber_beacon = StandardMaterial3D.new()
	_mat_amber_beacon.albedo_color = Color(1.0, 0.58, 0.18, 1.0)
	_mat_amber_beacon.emission_enabled = true
	_mat_amber_beacon.emission = Color(1.0, 0.55, 0.18, 1.0)
	_mat_amber_beacon.emission_energy_multiplier = 3.8

	_mat_white_beacon = StandardMaterial3D.new()
	_mat_white_beacon.albedo_color = Color(0.88, 0.95, 1.0, 1.0)
	_mat_white_beacon.emission_enabled = true
	_mat_white_beacon.emission = Color(0.85, 0.94, 1.0, 1.0)
	_mat_white_beacon.emission_energy_multiplier = 6.0


func _collect_existing_shafts() -> void:
	var root: Node = get_parent()
	if root == null:
		return
	var shaft_paths: Array[NodePath] = [
		^"Zone1_ConcreteBunker/VolumetricShaft_Bunker_01",
		^"Zone1_ConcreteBunker/VolumetricShaft_Bunker_02",
		^"Zone1_ConcreteBunker/VolumetricShaft_Bunker_03",
		^"Zone2_SwampMarsh/VolumetricShaft_Swamp_01",
		^"Zone2_SwampMarsh/VolumetricShaft_Swamp_02",
	]
	for p: NodePath in shaft_paths:
		var m: MeshInstance3D = root.get_node_or_null(p) as MeshInstance3D
		if m != null:
			_fake_shafts.append(m)


# --------------------------------------------------------------------------
# F4 Graphics Preset Switcher (RTX ULTRA vs iGPU LIGHT)
# --------------------------------------------------------------------------

func _apply_graphics_preset(rtx_ultra: bool) -> void:
	_rtx_ultra_enabled = rtx_ultra
	var vp: Viewport = get_viewport()
	var env: Environment = null
	if vp != null and vp.world_3d != null and vp.world_3d.environment != null:
		env = vp.world_3d.environment
	elif world_environment != null and world_environment.environment != null:
		env = world_environment.environment

	if env != null:
		if rtx_ultra:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.032
			env.volumetric_fog_albedo = Color(0.55, 0.62, 0.72, 1.0)
			env.volumetric_fog_anisotropy = 0.65
			env.volumetric_fog_detail_spread = 2.0
			env.volumetric_fog_temporal_reprojection_enabled = true
			env.volumetric_fog_temporal_reprojection_amount = 0.9
			env.ssao_enabled = true
			env.ssao_radius = 1.2
			env.ssao_intensity = 2.2
			env.ssr_enabled = true
			env.ssr_max_steps = 32
			env.ssil_enabled = false
			env.sdfgi_enabled = false
			env.glow_enabled = true
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_bloom = 0.15
		else:
			env.volumetric_fog_enabled = false
			env.ssr_enabled = false
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.sdfgi_enabled = false
			env.glow_enabled = false

	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0 if rtx_ultra else 0.65

	if _directional_light != null:
		_directional_light.shadow_enabled = rtx_ultra
		_directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if rtx_ultra else DirectionalLight3D.SHADOW_ORTHOGONAL

	for light: Light3D in _volumetric_lights:
		if is_instance_valid(light):
			light.shadow_enabled = rtx_ultra
			light.light_volumetric_fog_energy = 4.5 if rtx_ultra else 0.0

	if _auditor_1_light != null:
		_auditor_1_light.shadow_enabled = rtx_ultra
		_auditor_1_light.light_volumetric_fog_energy = 5.0 if rtx_ultra else 0.0
	if _auditor_2_light != null:
		_auditor_2_light.shadow_enabled = rtx_ultra
		_auditor_2_light.light_volumetric_fog_energy = 5.0 if rtx_ultra else 0.0
	if _beacon_omni_light != null:
		_beacon_omni_light.shadow_enabled = rtx_ultra
		_beacon_omni_light.light_volumetric_fog_energy = 3.5 if rtx_ultra else 0.0
	if _harvester_spotlight != null:
		_harvester_spotlight.shadow_enabled = rtx_ultra
		_harvester_spotlight.light_volumetric_fog_energy = 6.0 if rtx_ultra else 0.0

	for fv: FogVolume in _fog_volumes:
		if is_instance_valid(fv):
			fv.visible = rtx_ultra and (_active_act == 2)

	for shaft: MeshInstance3D in _fake_shafts:
		if is_instance_valid(shaft):
			shaft.visible = true

	if perf_hud != null:
		perf_hud.graphics_preset_label = PRESET_RTX_ULTRA if rtx_ultra else PRESET_IGPU_LIGHT

	_update_zone_gating(true)


# --------------------------------------------------------------------------
# Zone-Gated Processing & Checkpoints
# --------------------------------------------------------------------------

func _update_checkpoints_and_zone() -> void:
	var px: float = player.global_position.x
	for i: int in _checkpoints.size():
		if px >= _checkpoints[i].x - 1.0 and i > _current_cp_index:
			_current_cp_index = i
			player.set_checkpoint_spawn(_checkpoints[i])

	var desired_act: int = 1
	if px >= 182.0:
		desired_act = 3
	elif px >= 72.0:
		desired_act = 2

	if desired_act != _active_act:
		_active_act = desired_act
		_update_zone_gating(false)

	if perf_hud != null:
		match _active_act:
			1:
				var beat1: String = "Beat 1.1 (Blind Auditor Patrol)" if px < -2.0 else "Beat 1.2 (2.4m Ledge Bait & Sluice Gate)"
				perf_hud.narrative_status_label = "ACT I: THE SILENT BUNKER — %s [CP %d]" % [beat1, _current_cp_index]
			2:
				var beat2: String = "Beat 2.1 (Mire Stalker & Steam Pistons)" if px < 141.0 else "Beat 2.2 (220kg Beacon Crate Halo)"
				perf_hud.narrative_status_label = "ACT II: WHAT LURKS IN THE MUD — %s [CP %d]" % [beat2, _current_cp_index]
			3:
				var beat3: String = "Beat 3.1 (Harvester Shockwave Shield)" if px < 252.0 else "Beat 3.2 (100% Strain Climb & Sacrifice)"
				perf_hud.narrative_status_label = "ACT III: THE HARVESTER'S FIELD — %s [CP %d]" % [beat3, _current_cp_index]


func _update_zone_gating(force: bool) -> void:
	if not force and _act1_root == null:
		return
	var act1_on: bool = (_active_act == 1)
	var act2_on: bool = (_active_act == 2)
	var act3_on: bool = (_active_act == 3)

	# Never disable physics colliders: keep all zone roots at PROCESS_MODE_INHERIT and visible = true
	if _act1_root != null:
		_act1_root.visible = true
		_act1_root.process_mode = Node.PROCESS_MODE_INHERIT
	if _act2_root != null:
		_act2_root.visible = true
		_act2_root.process_mode = Node.PROCESS_MODE_INHERIT
	if _act3_root != null:
		_act3_root.visible = true
		_act3_root.process_mode = Node.PROCESS_MODE_INHERIT

	if _base_zone1 != null:
		_base_zone1.visible = true
		_base_zone1.process_mode = Node.PROCESS_MODE_INHERIT
	if _base_zone2 != null:
		_base_zone2.visible = true
		_base_zone2.process_mode = Node.PROCESS_MODE_INHERIT
	if _base_zone3 != null:
		_base_zone3.visible = true
		_base_zone3.process_mode = Node.PROCESS_MODE_INHERIT

	# Gate distant monster visuals & continuous 3D audio by Act
	if _auditor_1_buzz != null:
		if not act1_on and _auditor_1_buzz.playing:
			_auditor_1_buzz.stop()
	if _auditor_2_buzz != null:
		if not act1_on and _auditor_2_buzz.playing:
			_auditor_2_buzz.stop()
	if _mire_stalker != null:
		_mire_stalker.visible = act2_on
	if _harvester_root != null:
		_harvester_root.visible = act3_on
	if _act3_grass_multimesh != null:
		_act3_grass_multimesh.visible = act2_on or act3_on

	for l1: Light3D in _act1_lights:
		if is_instance_valid(l1):
			l1.visible = act1_on
	for l2: Light3D in _act2_lights:
		if is_instance_valid(l2):
			l2.visible = act2_on
	for l3: Light3D in _act3_lights:
		if is_instance_valid(l3):
			if l3 == _rescue_beacon_light and not _ending_triggered:
				l3.visible = false
			else:
				l3.visible = act3_on

	if _beacon_omni_light != null:
		_beacon_omni_light.visible = act2_on or act3_on

	for fv: FogVolume in _fog_volumes:
		if is_instance_valid(fv):
			fv.visible = act2_on and _rtx_ultra_enabled

	for p1: GPUParticles3D in _act1_particles:
		if is_instance_valid(p1):
			p1.emitting = act1_on and _rtx_ultra_enabled
	for p2: GPUParticles3D in _act2_particles:
		if is_instance_valid(p2):
			p2.emitting = act2_on and _rtx_ultra_enabled
	for p3: GPUParticles3D in _act3_particles:
		if is_instance_valid(p3):
			p3.emitting = act3_on and _rtx_ultra_enabled


func _pop_next_death_quote() -> String:
	if DEATH_QUOTES.is_empty():
		return ""
	if _quote_bag.is_empty():
		for i: int in DEATH_QUOTES.size():
			_quote_bag.append(i)
		_quote_bag.shuffle()
	var idx: int = _quote_bag.pop_back()
	return DEATH_QUOTES[idx]


func _trigger_capture(reason: String, source_dir_x: float = 0.0) -> void:
	if _respawning or _ending_triggered:
		return
	_respawning = true
	_respawn_timer = 0.0
	_respawn_teleported = false
	_respawn_stage = 0
	if player != null:
		player.trigger_death_collapse(source_dir_x)
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam != null:
		_cam_saved_fov = cam.fov
	if _death_quote_label != null:
		_death_quote_label.text = _pop_next_death_quote()
	if _death_panel != null:
		_death_panel.visible = false
		_death_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if perf_hud != null:
		perf_hud.narrative_status_label = "DEAD (%s) — Collapse -> Awaken at CP %d..." % [reason, _current_cp_index]


func _begin_awaken_fade_out() -> void:
	if _respawn_stage == 2:
		return
	_respawn_stage = 2
	_respawn_timer = 0.0
	if not _respawn_teleported:
		_respawn_teleported = true
		_restore_checkpoint_state()


func _process_respawn_fade(delta: float) -> void:
	_respawn_timer += delta
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null

	if _respawn_stage == 0:
		# Phase 0 (0.0s .. 1.1s): On-screen procedural death collapse + camera zoom-in & downward jolt
		var collapse_u: float = clampf(_respawn_timer / 1.1, 0.0, 1.0)
		if cam != null:
			cam.fov = lerpf(_cam_saved_fov, maxf(_cam_saved_fov - 6.5, 34.0), smoothstep(0.0, 1.0, collapse_u))
			cam.v_offset = -0.18 * smoothstep(0.0, 1.0, collapse_u) - sin(collapse_u * PI) * 0.09
		if _fade_rect != null:
			_fade_rect.color = Color(0.08, 0.01, 0.015, collapse_u * 0.32)
		if _respawn_timer >= 1.1:
			_respawn_stage = 1
			if _death_panel != null:
				_death_panel.visible = true
				_death_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	elif _respawn_stage == 1:
		# Phase 1 (1.1s .. 5.1s): Stark Playdead/Souls "Y O U   A R E   D E A D" + 105+ Quote Overlay
		var overlay_t: float = _respawn_timer - 1.1
		var fade_in_u: float = clampf(overlay_t / 0.45, 0.0, 1.0)
		if _fade_rect != null:
			_fade_rect.color = Color(
				lerpf(0.08, 0.015, fade_in_u),
				0.01,
				0.015,
				lerpf(0.32, 0.94, fade_in_u)
			)
		if _death_panel != null:
			_death_panel.visible = true
			_death_panel.modulate = Color(1.0, 1.0, 1.0, fade_in_u)
		if _death_footer_label != null:
			var pulse_a: float = 0.55 + 0.35 * sin(_time_accum * 4.2)
			_death_footer_label.modulate = Color(1.0, 1.0, 1.0, pulse_a)

		if overlay_t >= 4.0:
			_begin_awaken_fade_out()
	else:
		# Phase 2 (0.55s): Awaken at active checkpoint & fade out cleanly
		var out_u: float = clampf(_respawn_timer / 0.55, 0.0, 1.0)
		if _fade_rect != null:
			_fade_rect.color = Color(0.015, 0.01, 0.015, (1.0 - out_u) * 0.94)
		if _death_panel != null:
			_death_panel.modulate = Color(1.0, 1.0, 1.0, maxf(0.0, 1.0 - out_u * 2.2))
		if out_u >= 1.0:
			_respawning = false
			_respawn_stage = 0
			if _death_panel != null:
				_death_panel.visible = false
			if _fade_rect != null:
				_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)


func _restore_checkpoint_state() -> void:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam != null:
		cam.v_offset = 0.0
		cam.fov = _cam_saved_fov
	if player == null:
		return
	var cp_pos: Vector3 = _checkpoints[_current_cp_index]
	player.external_strain_floor = 0.0
	player.teleport_to_checkpoint(cp_pos)

	# Reset monsters & dynamic puzzle elements cleanly
	_auditor_1_exposure = 0.0
	_auditor_2_exposure = 0.0
	_auditor_1_alert_timer = 0.0
	_auditor_2_alert_timer = 0.0
	_sustained_run_timer = 0.0
	_mire_strike_exposure = 0.0
	_mire_agitation = 0.0
	_shockwave_timer = 0.0
	_horn_played_this_cycle = false

	if _current_cp_index <= 1:
		_sluice_1_open_timer = 0.0
		_sluice_1_height = 0.95
		if _sluice_gate_1 != null:
			_sluice_gate_1.position.y = _sluice_1_height

	if beacon_crate != null and _current_cp_index < _crate_checkpoints.size():
		var crate_pos: Vector3 = _crate_checkpoints[_current_cp_index]
		if _current_cp_index == 4 and (_crate_reached_marsh_exit or beacon_crate.global_position.x >= 177.8):
			_crate_reached_marsh_exit = true
			_crate_lifted_to_field = true
			_crate_hoisting = false
			crate_pos = _crate_hoist_target
			_crate_checkpoints[4] = _crate_hoist_target
			_checkpoints[4] = Vector3(183.2, 1.80, 0.0)
			player.teleport_to_checkpoint(_checkpoints[4])
		else:
			_crate_lifted_to_field = (_current_cp_index >= 5)
			_crate_hoisting = false
		beacon_crate.linear_velocity = Vector3.ZERO
		beacon_crate.angular_velocity = Vector3.ZERO
		beacon_crate.global_position = crate_pos

	if _current_cp_index >= 5:
		_hound_active = false
		_hound_crushed = false
		_hound_x = 238.0
		if _hound_pursuer != null:
			_hound_pursuer.visible = false

	_update_checkpoints_and_zone()
	_update_zone_gating(true)


# --------------------------------------------------------------------------
# Player Acoustic Event Hooks (Feeds Blind Auditor & Mire Stalker)
# --------------------------------------------------------------------------

func _on_player_kinetic_state_changed(new_state: StringName, _prev_state: StringName) -> void:
	if player == null or _respawning or _ending_triggered:
		return
	var px: float = player.global_position.x
	if _active_act == 1:
		# Stealth Whitelist: ONLY Idle, CreepWalk, and ClimbLedge are silent.
		# Trigger acoustic alerts on HardLand, JumpStart, or Run (> 0.12s).
		if new_state == PlayerController3D.STATE_HARD_LAND:
			if _auditor_2 != null and (absf(_auditor_2.position.x - px) <= 22.0 or (px >= -5.0 and px <= 15.0)):
				_auditor_2_target_x = px
				_auditor_2_alert_timer = 4.5
				_auditor_2_baited_timer = 10.5
				if _auditor_2_audio != null and not _auditor_2_audio.playing:
					_auditor_2_audio.pitch_scale = 1.35
					_auditor_2_audio.play()
			if _auditor_1 != null and absf(_auditor_1.position.x - px) <= 22.0:
				_auditor_1_target_x = clampf(px, -18.5, 8.0)
				_auditor_1_alert_timer = 3.2
		elif new_state == PlayerController3D.STATE_JUMP_START:
			if px <= 8.0 and _auditor_1 != null and absf(_auditor_1.position.x - px) <= 22.0:
				_auditor_1_target_x = clampf(px, -18.5, 8.0)
				_auditor_1_alert_timer = maxf(_auditor_1_alert_timer, 2.4)
			elif px > -2.0 and _auditor_2 != null and absf(_auditor_2.position.x - px) <= 22.0:
				_auditor_2_target_x = px
				_auditor_2_alert_timer = maxf(_auditor_2_alert_timer, 2.4)


func _on_player_stride_phase_triggered(_foot_index: int, foot_global_pos: Vector3, _impact_velocity: float, _is_scuff: bool) -> void:
	if player == null or _respawning or _ending_triggered:
		return
	var px: float = foot_global_pos.x
	var st: StringName = player.get_state_name()

	if _active_act == 1:
		# Trigger acoustic alerts on HardLand, JumpStart, or Run (> 0.12s) within 22.0m hearing radius
		var loud_step: bool = (
			st == PlayerController3D.STATE_HARD_LAND
			or st == PlayerController3D.STATE_JUMP_START
			or (st == PlayerController3D.STATE_RUN and _sustained_run_timer > 0.12)
		)
		if loud_step:
			if px <= 8.0 and _auditor_1 != null and absf(_auditor_1.position.x - px) <= 22.0:
				_auditor_1_target_x = clampf(px, -18.5, 8.0)
				_auditor_1_alert_timer = maxf(_auditor_1_alert_timer, 2.4)
			if px >= -2.0 and px < 72.0 and _auditor_2 != null and absf(_auditor_2.position.x - px) <= 22.0:
				_auditor_2_target_x = px
				_auditor_2_alert_timer = maxf(_auditor_2_alert_timer, 2.5)

	elif _active_act == 2 and not _steam_mask_active:
		var wetness: float = foley_director.get_shoe_wetness() if foley_director != null else 0.0
		var in_mud: bool = (st == PlayerController3D.STATE_WADING_SWAMP or player.is_in_swamp())
		var wet_sprint_near_edge: bool = (not in_mud and wetness > 0.30 and st == PlayerController3D.STATE_RUN)
		if in_mud or wet_sprint_near_edge:
			_mire_agitation = minf(_mire_agitation + (0.45 if st == PlayerController3D.STATE_RUN else 0.22), 1.5)


# --------------------------------------------------------------------------
# ACT I LOGIC: The Blind Auditor & Crushing Sluice Gate
# --------------------------------------------------------------------------

func _process_act1_bunker(delta: float) -> void:
	var px: float = player.global_position.x
	var st: StringName = player.get_state_name()
	if st == PlayerController3D.STATE_RUN:
		_sustained_run_timer += delta
	else:
		_sustained_run_timer = 0.0

	var is_silent_state: bool = (
		st == PlayerController3D.STATE_IDLE
		or st == PlayerController3D.STATE_CREEP_WALK
		or st == PlayerController3D.STATE_CLIMB_LEDGE
	)
	var is_loud: bool = (
		st == PlayerController3D.STATE_HARD_LAND
		or st == PlayerController3D.STATE_JUMP_START
		or (st == PlayerController3D.STATE_RUN and _sustained_run_timer > 0.12)
	)

	# --- Drone 1 (Beat 1.1: Expanded Start-Zone Pursuit X = -18.5m to 8.0m, 22.0m hearing) ---
	if _auditor_1 != null:
		_auditor_1_alert_timer = maxf(_auditor_1_alert_timer - delta, 0.0)
		var dist_1: float = absf(px - _auditor_1.position.x)
		if is_loud and px <= 8.0 and dist_1 <= 22.0:
			_auditor_1_target_x = clampf(px, -18.5, 8.0)
			_auditor_1_alert_timer = 2.5
		elif _auditor_1_alert_timer <= 0.0:
			_auditor_1_target_x = -8.5 + sin(_time_accum * 0.85) * 9.5

		# +30% speed boost: Patrol 2.4 m/s, Alert Chase 5.0 m/s
		var speed_1: float = 5.0 if _auditor_1_alert_timer > 0.0 else 2.4
		_auditor_1.position.x = move_toward(_auditor_1.position.x, _auditor_1_target_x, speed_1 * delta)
		_auditor_1_buzz_phase = _fill_drone_buzz_audio(_auditor_1_buzz, _auditor_1_buzz_phase, _auditor_1_alert_timer > 0.0 or _auditor_1_exposure > 0.1)

		var in_shadow_or_climb_1: bool = (
			st == PlayerController3D.STATE_CLIMB_LEDGE
			or ((absf(px - (-13.0)) < 1.35 or absf(px - (-6.8)) < 1.35) and is_silent_state)
		)
		dist_1 = absf(px - _auditor_1.position.x)
		if dist_1 < 1.65 and not in_shadow_or_climb_1 and (is_loud or _auditor_1_alert_timer > 0.0 or (dist_1 < 0.95 and not is_silent_state)):
			_auditor_1_exposure += delta
			if _auditor_1_light != null:
				_auditor_1_light.light_color = Color(1.0, 0.08, 0.08, 1.0)
				_auditor_1_light.light_energy = 9.5
			if _auditor_1_exposure > 0.35 and _auditor_1_exposure <= 1.6:
				player.trigger_damage_flinch(_auditor_1.position.x - px)
			if _auditor_1_exposure > 1.6:
				_trigger_capture("The Blind Auditor Drone", _auditor_1.position.x - px)
				return
		else:
			_auditor_1_exposure = maxf(_auditor_1_exposure - delta * 3.0, 0.0)
			if _auditor_1_light != null:
				_auditor_1_light.light_color = Color(1.0, 0.18, 0.14, 1.0) if _auditor_1_alert_timer > 0.0 else Color(0.95, 0.32, 0.22, 1.0)
				_auditor_1_light.light_energy = 6.5 if _auditor_1_alert_timer > 0.0 else 4.2

	# --- Drone 2 (Beat 1.2: 2.4m Drop Ledge Bait & Sluice Gate X = -2m to 68m, 22.0m hearing) ---
	if _auditor_2 != null:
		_auditor_2_alert_timer = maxf(_auditor_2_alert_timer - delta, 0.0)
		_auditor_2_baited_timer = maxf(_auditor_2_baited_timer - delta, 0.0)
		var dist_2: float = absf(px - _auditor_2.position.x)
		if is_loud and px >= -2.0 and px < 68.0 and dist_2 <= 22.0:
			_auditor_2_target_x = px
			_auditor_2_alert_timer = 2.6
		elif _auditor_2_baited_timer > 0.0:
			# Holds near the 2.4m drop zone while baited so player can CreepWalk to lever!
			_auditor_2_target_x = 0.5 + sin(_time_accum * 1.8) * 2.0
		elif _auditor_2_alert_timer <= 0.0:
			_auditor_2_target_x = 28.0 + sin(_time_accum * 0.65) * 14.0

		# +30% speed boost: Patrol 2.9 m/s, Alert Chase 5.5 m/s
		var speed_2: float = 5.5 if (_auditor_2_alert_timer > 0.0 or _auditor_2_baited_timer > 0.0) else 2.9
		_auditor_2.position.x = move_toward(_auditor_2.position.x, _auditor_2_target_x, speed_2 * delta)
		_auditor_2_buzz_phase = _fill_drone_buzz_audio(_auditor_2_buzz, _auditor_2_buzz_phase, _auditor_2_alert_timer > 0.0 or _auditor_2_baited_timer > 0.0 or _auditor_2_exposure > 0.1)

		var in_shadow_or_climb_2: bool = (
			st == PlayerController3D.STATE_CLIMB_LEDGE
			or (is_silent_state and _auditor_2_alert_timer <= 0.0)
			or (absf(px - 14.5) < 1.65 and player.global_position.y < 1.15)
		)
		dist_2 = absf(px - _auditor_2.position.x)
		if dist_2 < 1.85 and not in_shadow_or_climb_2:
			_auditor_2_exposure += delta
			if _auditor_2_light != null:
				_auditor_2_light.light_color = Color(1.0, 0.05, 0.05, 1.0)
				_auditor_2_light.light_energy = 10.0
			if _auditor_2_exposure > 0.35 and _auditor_2_exposure <= 1.6:
				player.trigger_damage_flinch(_auditor_2.position.x - px)
			if _auditor_2_exposure > 1.6:
				_trigger_capture("The Blind Auditor Arc-Discharge", _auditor_2.position.x - px)
				return
		else:
			_auditor_2_exposure = maxf(_auditor_2_exposure - delta * 3.0, 0.0)
			if _auditor_2_light != null:
				_auditor_2_light.light_color = Color(1.0, 0.14, 0.12, 1.0) if _auditor_2_alert_timer > 0.0 else Color(0.95, 0.30, 0.20, 1.0)
				_auditor_2_light.light_energy = 7.0 if _auditor_2_alert_timer > 0.0 else 4.5

	# --- Counterweight Lever (X = 24m) & Crushing Steel Sluice Gate (X = 38m) ---
	if absf(px - 24.0) < 1.6 and player.global_position.y < 2.2:
		if _sluice_1_open_timer <= 0.5:
			_sluice_1_open_timer = 8.5
			if _sluice_audio_1 != null:
				_sluice_audio_1.pitch_scale = 0.75
				_sluice_audio_1.play()

	if _sluice_1_open_timer > 0.0:
		_sluice_1_open_timer = maxf(_sluice_1_open_timer - delta, 0.0)
		var target_h: float = 3.35 if _sluice_1_open_timer > 2.5 else 0.95
		var gate_rate: float = 3.2 if target_h > _sluice_1_height else 0.95
		_sluice_1_height = move_toward(_sluice_1_height, target_h, gate_rate * delta)
	else:
		_sluice_1_height = move_toward(_sluice_1_height, 0.95, 1.8 * delta)

	if _sluice_gate_1 != null:
		_sluice_gate_1.position.y = _sluice_1_height
		# Hazard edge flinch & crushing check if gate descends onto player
		if absf(px - 38.0) >= 0.75 and absf(px - 38.0) < 1.38 and _sluice_1_height < 2.25 and _sluice_1_open_timer <= 2.5:
			player.trigger_damage_flinch(38.0 - px)
		if absf(px - 38.0) < 0.75 and _sluice_1_height < 1.95 and _sluice_1_height > 0.98 and _sluice_1_open_timer <= 2.5:
			_trigger_capture("Crushing Steel Sluice Gate", 38.0 - px)
			return
	if _lever_pivot != null:
		var lever_angle: float = -35.0 if _sluice_1_open_timer > 0.0 else 25.0
		_lever_pivot.rotation_degrees.z = move_toward(_lever_pivot.rotation_degrees.z, lever_angle, 120.0 * delta)


# --------------------------------------------------------------------------
# ACT II LOGIC: The Mire Stalker, Steam Pistons & 220 kg Beacon Crate
# --------------------------------------------------------------------------

func _process_act2_swamp(delta: float) -> void:
	var px: float = player.global_position.x
	var st: StringName = player.get_state_name()

	# --- High-Pressure Steam Pistons (3.5s cycle at X = 120m and X = 133m) ---
	_piston_cycle_timer = fmod(_piston_cycle_timer + delta, 3.5)
	var piston_slam_phase: bool = (_piston_cycle_timer >= 2.2 and _piston_cycle_timer <= 3.1)
	_steam_mask_active = (_piston_cycle_timer >= 2.0 and _piston_cycle_timer <= 3.45)

	var piston_y: float = 1.05 if piston_slam_phase else 3.45
	var piston_rate: float = 14.0 if piston_slam_phase else 2.8
	if _piston_1_head != null:
		_piston_1_head.position.y = move_toward(_piston_1_head.position.y, piston_y, piston_rate * delta)
		if piston_slam_phase and absf(px - 120.0) >= 1.15 and absf(px - 120.0) < 1.95 and player.global_position.y < 2.2:
			player.trigger_damage_flinch(120.0 - px)
		if piston_slam_phase and absf(px - 120.0) < 1.15 and player.global_position.y < 2.2:
			_trigger_capture("High-Pressure Steam Piston", 120.0 - px)
			return
	if _piston_2_head != null:
		_piston_2_head.position.y = move_toward(_piston_2_head.position.y, piston_y, piston_rate * delta)
		if piston_slam_phase and absf(px - 133.0) >= 1.15 and absf(px - 133.0) < 1.95 and player.global_position.y < 2.2:
			player.trigger_damage_flinch(133.0 - px)
		if piston_slam_phase and absf(px - 133.0) < 1.15 and player.global_position.y < 2.2:
			_trigger_capture("High-Pressure Steam Piston", 133.0 - px)
			return

	if _piston_1_steam != null:
		_piston_1_steam.emitting = _steam_mask_active and _rtx_ultra_enabled
	if _piston_2_steam != null:
		_piston_2_steam.emitting = _steam_mask_active and _rtx_ultra_enabled

	# --- The Mire Stalker (Submerged Tendril Horror + Reactive Swamp Shader) ---
	var in_mud: bool = (st == PlayerController3D.STATE_WADING_SWAMP or player.is_in_swamp())
	var wetness: float = foley_director.get_shoe_wetness() if foley_director != null else 0.0
	var wet_alert_on_island: bool = (not in_mud and wetness > 0.30 and st == PlayerController3D.STATE_RUN and px >= 75.0 and px <= 182.0)

	var crate_x: float = beacon_crate.global_position.x if beacon_crate != null else 145.5
	var dist_player_to_crate: float = absf(px - crate_x)
	var protected_by_beacon: bool = (dist_player_to_crate <= 3.85 and px >= 141.0)

	if (in_mud or wet_alert_on_island) and not _steam_mask_active and not protected_by_beacon:
		var move_speed: float = 5.4 if st == PlayerController3D.STATE_RUN else 3.2
		if px > 149.0:
			# Final swamp trench: lethal without the Beacon Crate halo!
			move_speed = 7.5
		_mire_x = move_toward(_mire_x, px, move_speed * delta)
		_mire_agitation = move_toward(_mire_agitation, 1.35, 1.5 * delta)
	else:
		# Repelled by the 220 kg Beacon Crate's 3.8m warm volumetric OmniLight3D halo!
		if absf(_mire_x - crate_x) < 3.9:
			var repel_dir: float = -1.0 if _mire_x <= crate_x else 1.0
			_mire_x = move_toward(_mire_x, crate_x + repel_dir * 4.2, 4.8 * delta)
			_mire_agitation = move_toward(_mire_agitation, 0.85, 1.2 * delta)
		else:
			var patrol_center: float = clampf(px - 4.5, 80.0, 178.0)
			_mire_x = move_toward(_mire_x, patrol_center + sin(_time_accum * 1.4) * 3.0, 2.0 * delta)
			_mire_agitation = move_toward(_mire_agitation, 0.35, 0.8 * delta)

	if _mire_stalker != null:
		_mire_stalker.position.x = _mire_x
		_mire_stalker.position.y = -0.15 + sin(_time_accum * 4.0) * 0.08 * _mire_agitation
		for idx: int in _mire_tendrils.size():
			var tendril: MeshInstance3D = _mire_tendrils[idx]
			var phase: float = _time_accum * (3.2 + float(idx) * 0.45) + float(idx) * 1.1
			tendril.rotation_degrees.z = sin(phase) * (14.0 + 18.0 * _mire_agitation)
			tendril.position.y = 0.25 + sin(phase * 1.3) * 0.18 * _mire_agitation

	# Feed Mire Stalker coordinates into Reactive Swamp Surface Shader!
	if foley_director != null and foley_director.swamp_surface_material != null:
		var smat: ShaderMaterial = foley_director.swamp_surface_material
		smat.set_shader_parameter(&"monster_world_pos", Vector3(_mire_x, 0.0, 0.0))
		smat.set_shader_parameter(&"monster_ripple_intensity", clampf(_mire_agitation, 0.2, 1.5))

	# Check Mire Stalker flinch & capture
	if (in_mud or wet_alert_on_island) and not protected_by_beacon and not _steam_mask_active:
		if absf(px - _mire_x) < 1.35:
			_mire_strike_exposure += delta
			if _mire_strike_exposure > 0.14 and _mire_strike_exposure <= 0.42:
				player.trigger_damage_flinch(_mire_x - px)
			if _mire_strike_exposure > 0.42:
				_trigger_capture("The Mire Stalker", _mire_x - px)
				return
		else:
			_mire_strike_exposure = maxf(_mire_strike_exposure - delta * 1.5, 0.0)
	else:
		_mire_strike_exposure = 0.0

	# --- Swamp Shoreline Auto-Hoist & Unwedge Out of Water (X = 177.8m..185.2m) ---
	if beacon_crate != null:
		var cx: float = beacon_crate.global_position.x
		var cy: float = beacon_crate.global_position.y
		# Unwedge / Proximity Hoist: as soon as crate is within 1.5m of the marsh exit wall (or wedged against it)
		if not _crate_hoisting and cx >= 177.8 and cx < 184.6 and cy < 1.65:
			_crate_hoisting = true
			_crate_hoist_timer = 0.0
			_crate_hoist_start = beacon_crate.global_position
			_crate_reached_marsh_exit = true
			_crate_checkpoints[4] = _crate_hoist_target
			_checkpoints[4] = Vector3(183.2, 1.80, 0.0)
			if _current_cp_index == 4:
				player.set_checkpoint_spawn(_checkpoints[4])

		if _crate_hoisting:
			_crate_hoist_timer += delta
			var u: float = smoothstep(0.0, 1.0, clampf(_crate_hoist_timer / 0.55, 0.0, 1.0))
			var lift_u: float = smoothstep(0.0, 1.0, clampf(_crate_hoist_timer / 0.38, 0.0, 1.0))
			beacon_crate.sleeping = false
			beacon_crate.linear_velocity = Vector3.ZERO
			beacon_crate.angular_velocity = Vector3.ZERO
			beacon_crate.global_position = Vector3(
				lerpf(_crate_hoist_start.x, _crate_hoist_target.x, u),
				lerpf(_crate_hoist_start.y, _crate_hoist_target.y, lift_u),
				0.0
			)
			if _crate_hoist_timer >= 0.55:
				_crate_hoisting = false
				_crate_lifted_to_field = true
				beacon_crate.global_position = _crate_hoist_target
				beacon_crate.linear_velocity = Vector3.ZERO

		# Also allow crate pushed off the upper dry deck (X >= 186.5) to settle smoothly into Act III
		if _crate_lifted_to_field and px >= 186.5 and beacon_crate.global_position.x < 186.0:
			beacon_crate.linear_velocity = Vector3.ZERO
			beacon_crate.global_position = Vector3(189.5, 0.9, 0.0)

		if _act3_grass_material != null and px >= 172.0:
			_act3_grass_material.set_shader_parameter(&"player_world_pos", player.global_position)
			_act3_grass_material.set_shader_parameter(&"crate_world_pos", beacon_crate.global_position)


# --------------------------------------------------------------------------
# ACT III LOGIC: The Harvester Titan, Gale Shockwaves, Hound & Climax
# --------------------------------------------------------------------------

func _process_act3_field(delta: float) -> void:
	var px: float = player.global_position.x
	if beacon_crate != null and not _crate_lifted_to_field and px >= 185.0:
		_crate_lifted_to_field = true
		beacon_crate.linear_velocity = Vector3.ZERO
		beacon_crate.global_position = Vector3(190.5, 0.9, 0.0)

	var crate_x: float = beacon_crate.global_position.x if beacon_crate != null else px

	# --- Harvester Titan Background Stalk & 7.0s Gale Shockwave Cycle (X = 185m..253m) ---
	if _harvester_root != null:
		var target_hx: float = clampf(px + 4.0, 195.0, 260.0)
		_harvester_root.position.x = move_toward(_harvester_root.position.x, target_hx, 2.2 * delta)
		for i: int in _harvester_legs.size():
			var leg: Node3D = _harvester_legs[i]
			leg.rotation_degrees.z = sin(_time_accum * 1.6 + float(i) * 2.1) * 8.5

	var target_gust: float = 0.0
	if px >= 188.0 and px < 253.0:
		_shockwave_timer += delta
		if _shockwave_timer >= _shockwave_cycle_sec:
			_shockwave_timer = 0.0
			_horn_played_this_cycle = false

		var time_until_wave: float = _shockwave_cycle_sec - _shockwave_timer
		var in_telegraph: bool = (time_until_wave <= _shockwave_telegraph_sec + _shockwave_active_sec and time_until_wave > _shockwave_active_sec)
		var in_shockwave: bool = (time_until_wave <= _shockwave_active_sec)
		if in_shockwave:
			target_gust = 1.0
		elif in_telegraph:
			target_gust = 0.38

		if in_telegraph and not _horn_played_this_cycle:
			_horn_played_this_cycle = true
			if _harvester_horn_audio != null:
				_harvester_horn_audio.pitch_scale = 0.52
				_harvester_horn_audio.play()

		if _harvester_spotlight != null:
			if in_shockwave:
				_harvester_spotlight.light_energy = 14.0
				_harvester_spotlight.light_color = Color(1.0, 0.95, 0.88, 1.0)
			elif in_telegraph:
				var pulse: float = 0.5 + 0.5 * sin(_time_accum * 14.0)
				_harvester_spotlight.light_energy = lerpf(5.0, 11.0, pulse)
				_harvester_spotlight.light_color = Color(1.0, 0.65, 0.45, 1.0)
			else:
				_harvester_spotlight.light_energy = 5.0
				_harvester_spotlight.light_color = Color(0.82, 0.90, 1.0, 1.0)

		if in_telegraph and px >= 192.0 and absf(px - crate_x) >= 1.8 and time_until_wave <= _shockwave_active_sec + 0.9:
			player.trigger_damage_flinch(1.0)

		if in_shockwave and px >= 192.0:
			# Deterministic Crate Shadow Shelter Check: abs(player.x - crate.x) < 1.8m
			var sheltered_by_crate: bool = absf(px - crate_x) < 1.8
			if not sheltered_by_crate:
				_trigger_capture("Harvester Gale Shockwave (Hide in Crate Shadow)", 1.0)
				return
	else:
		_shockwave_timer = 0.0

	_act3_gust_intensity = move_toward(_act3_gust_intensity, target_gust, (4.5 if target_gust > _act3_gust_intensity else 1.8) * delta)
	if _act3_grass_material != null:
		_act3_grass_material.set_shader_parameter(&"player_world_pos", player.global_position)
		var c_pos: Vector3 = beacon_crate.global_position if beacon_crate != null else Vector3(0.0, -10.0, 0.0)
		_act3_grass_material.set_shader_parameter(&"crate_world_pos", c_pos)
		_act3_grass_material.set_shader_parameter(&"gust_intensity", _act3_gust_intensity)

	# --- Beat 3.2: Climax Slope (60% -> 95% -> 100% Strain Factor) & Hound Pursuer ---
	if px >= 253.0 and not _ending_triggered:
		var slope_t: float = clampf((px - 253.0) / 34.0, 0.0, 1.0)
		var target_strain_floor: float = lerpf(0.60, 1.00, slope_t)
		player.external_strain_floor = target_strain_floor

		if not _hound_active and px >= 255.0:
			_hound_active = true
			_hound_x = px - 14.0
			if _hound_pursuer != null:
				_hound_pursuer.visible = true
			if _hound_audio != null:
				_hound_audio.pitch_scale = 0.9
				_hound_audio.play()

		if _hound_active and not _hound_crushed and _hound_pursuer != null:
			var hound_speed: float = 2.05 if player.get_state_name() == PlayerController3D.STATE_PUSH_PULL_HEAVY else 3.4
			_hound_x = move_toward(_hound_x, px, hound_speed * delta)
			var slope_y: float = maxf(0.0, (_hound_x - 253.0) * 0.16)
			_hound_pursuer.position = Vector3(_hound_x, slope_y + 0.55 + absf(sin(_time_accum * 9.0)) * 0.18, 0.0)
			if px - _hound_x >= 0.95 and px - _hound_x < 2.25:
				player.trigger_damage_flinch(_hound_x - px)
			if px - _hound_x < 0.95:
				_trigger_capture("The Hound Pursuer", _hound_x - px)
				return

		# Check Counterweight Cradle Lock at Summit (X >= 286.5m)
		if crate_x >= 286.0 or px >= 287.5:
			_trigger_climax_sacrifice()
	else:
		player.external_strain_floor = 0.0


func _trigger_climax_sacrifice() -> void:
	_ending_triggered = true
	_ending_timer = 0.0
	_hound_crushed = true
	if player != null:
		player.external_strain_floor = 0.0

	if _trapdoor_mesh != null:
		_trapdoor_mesh.rotation_degrees.z = -78.0

	if _rescue_beacon_light != null:
		_rescue_beacon_light.visible = true
		_rescue_beacon_light.light_energy = 16.0
	if _rescue_beacon_shaft != null:
		_rescue_beacon_shaft.visible = true

	if _harvester_horn_audio != null:
		_harvester_horn_audio.pitch_scale = 0.68
		_harvester_horn_audio.play()

	if camera_rig != null and _ending_cam_region != null:
		camera_rig.register_region(_ending_cam_region)

	if perf_hud != null:
		perf_hud.narrative_status_label = "CLIMAX & CATHARSIS — Rescue Beacon Ignited (Strain 0%)"


func _process_ending_sequence(delta: float) -> void:
	_ending_timer += delta
	if _hound_pursuer != null and _hound_pursuer.visible:
		_hound_pursuer.position.y -= 14.0 * delta
		_hound_pursuer.rotation_degrees.z += 180.0 * delta
		if _hound_pursuer.position.y < -20.0:
			_hound_pursuer.visible = false

	if beacon_crate != null and _ending_timer < 2.5:
		beacon_crate.sleeping = false
		beacon_crate.linear_velocity = Vector3(4.0, -9.5, 0.0)

	if _title_panel != null and _ending_timer >= 2.2:
		_title_panel.visible = true
		var fade_a: float = clampf((_ending_timer - 2.2) / 3.0, 0.0, 1.0)
		_title_panel.modulate = Color(1.0, 1.0, 1.0, fade_a)


# --------------------------------------------------------------------------
# UI Overlay: Death Screen ("YOU ARE DEAD" + 108 Quotes) & End Title
# --------------------------------------------------------------------------

func _build_fade_and_title_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "NarrativeOverlayLayer"
	layer.layer = 48
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "RespawnFadeRect"
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)

	_death_panel = Control.new()
	_death_panel.name = "DeathOverlayPanel"
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.visible = false
	_death_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(_death_panel)

	var divider_top: ColorRect = ColorRect.new()
	divider_top.color = Color(0.55, 0.12, 0.12, 0.45)
	divider_top.set_anchors_preset(Control.PRESET_CENTER)
	divider_top.position = Vector2(-260.0, -118.0)
	divider_top.size = Vector2(520.0, 1.0)
	divider_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.add_child(divider_top)

	_death_header_label = Label.new()
	_death_header_label.text = "Y O U   A R E   D E A D"
	_death_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_header_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_header_label.position = Vector2(-380.0, -108.0)
	_death_header_label.custom_minimum_size = Vector2(760.0, 56.0)
	_death_header_label.add_theme_font_size_override(&"font_size", 40)
	_death_header_label.add_theme_color_override(&"font_color", Color(0.78, 0.16, 0.16, 0.96))
	_death_panel.add_child(_death_header_label)

	var divider_bottom: ColorRect = ColorRect.new()
	divider_bottom.color = Color(0.55, 0.12, 0.12, 0.45)
	divider_bottom.set_anchors_preset(Control.PRESET_CENTER)
	divider_bottom.position = Vector2(-260.0, -44.0)
	divider_bottom.size = Vector2(520.0, 1.0)
	divider_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.add_child(divider_bottom)

	_death_quote_label = Label.new()
	_death_quote_label.text = ""
	_death_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_quote_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_death_quote_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_quote_label.position = Vector2(-420.0, -24.0)
	_death_quote_label.custom_minimum_size = Vector2(840.0, 120.0)
	_death_quote_label.add_theme_font_size_override(&"font_size", 18)
	_death_quote_label.add_theme_color_override(&"font_color", Color(0.82, 0.84, 0.88, 0.92))
	_death_panel.add_child(_death_quote_label)

	_death_footer_label = Label.new()
	_death_footer_label.text = "[ PRESS SPACE / ENTER TO AWAKEN ]"
	_death_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_footer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_footer_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_footer_label.position = Vector2(-320.0, 128.0)
	_death_footer_label.custom_minimum_size = Vector2(640.0, 36.0)
	_death_footer_label.add_theme_font_size_override(&"font_size", 14)
	_death_footer_label.add_theme_color_override(&"font_color", Color(0.56, 0.60, 0.66, 0.85))
	_death_panel.add_child(_death_footer_label)

	_title_panel = Control.new()
	_title_panel.name = "EndTitlePanel"
	_title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_panel.visible = false
	_title_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(_title_panel)

	_title_label = Label.new()
	_title_label.text = "S I L E N T   W E I G H T"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.position = Vector2(-320.0, -60.0)
	_title_label.custom_minimum_size = Vector2(640.0, 60.0)
	_title_label.add_theme_font_size_override(&"font_size", 42)
	_title_label.add_theme_color_override(&"font_color", Color(0.90, 0.93, 0.96, 1.0))
	_title_panel.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = "A PLAYDEAD-INSPIRED 2.5D SHORT EXPERIENCE"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER)
	_subtitle_label.position = Vector2(-320.0, 8.0)
	_subtitle_label.custom_minimum_size = Vector2(640.0, 36.0)
	_subtitle_label.add_theme_font_size_override(&"font_size", 15)
	_subtitle_label.add_theme_color_override(&"font_color", Color(0.62, 0.68, 0.75, 0.85))
	_title_panel.add_child(_subtitle_label)


# --------------------------------------------------------------------------
# 3-Act Continuous Level Assembly (X = -22m to X = 305m)
# --------------------------------------------------------------------------

func _assemble_three_act_world() -> void:
	var root: Node = get_parent()
	if root == null:
		return

	_act1_root = Node3D.new()
	_act1_root.name = "Act1_SilentBunker_Ext"
	add_child(_act1_root)

	_act2_root = Node3D.new()
	_act2_root.name = "Act2_SwampMarsh_Ext"
	add_child(_act2_root)

	_act3_root = Node3D.new()
	_act3_root.name = "Act3_HarvesterField_Ext"
	add_child(_act3_root)

	# Reposition existing Zone 2 & Zone 3 bases to align with the 300m blueprint (with overlapping seams)
	var zone2_node: Node3D = root.get_node_or_null(^"Zone2_SwampMarsh") as Node3D
	if zone2_node != null:
		var floor_swamp: StaticBody3D = zone2_node.get_node_or_null(^"Floor_Swamp") as StaticBody3D
		if floor_swamp != null:
			floor_swamp.position = Vector3(85.0, -1.0, 0.0)
		var hazard_swamp: Area3D = zone2_node.get_node_or_null(^"SwampHazardArea") as Area3D
		if hazard_swamp != null:
			hazard_swamp.position = Vector3(85.0, 0.75, 0.0)
		var plane_swamp: MeshInstance3D = zone2_node.get_node_or_null(^"SwampVisualPlane") as MeshInstance3D
		if plane_swamp != null:
			plane_swamp.position = Vector3(85.0, 0.1, 0.0)

	var zone3_node: Node3D = root.get_node_or_null(^"Zone3_WindyField") as Node3D
	if zone3_node != null:
		var floor_field: StaticBody3D = zone3_node.get_node_or_null(^"Floor_Field") as StaticBody3D
		if floor_field != null:
			floor_field.position = Vector3(197.5, -1.0, 0.0)

	_build_act1_bunker_world(root)
	_build_act2_swamp_world(root, zone2_node)
	_build_act3_field_world(root)


func _build_act1_bunker_world(root: Node) -> void:
	# Extend Bunker Floor from X = -2.0m to X = 78.0m (overlaps Drop Floor and Swamp Floor with zero seam gap)
	_create_surface_box(_act1_root, "Floor_Bunker_Gallery", Vector3(38.0, -1.0, 0.0), Vector3(80.0, 2.0, 6.0), &"concrete_dry", _mat_concrete_dark)
	_create_surface_box(_act1_root, "Ceiling_Bunker_Gallery", Vector3(38.0, 7.5, 0.0), Vector3(80.0, 1.0, 6.0), &"concrete_dry", _mat_concrete_dark)
	_create_surface_box(_act1_root, "BackWall_Bunker_Gallery", Vector3(38.0, 4.0, -3.0), Vector3(80.0, 9.0, 1.0), &"concrete_dry", _mat_concrete_dark)

	# Shadow Cover Architecture & Counterweight Lever (X = 24m) + Crushing Sluice Gate (X = 38m)
	_create_surface_box(_act1_root, "ShadowCanopy_01", Vector3(12.0, 3.6, 0.0), Vector3(2.8, 0.4, 3.0), &"concrete_dry", _mat_metal_rust)
	_create_surface_box(_act1_root, "ShadowCanopy_02", Vector3(52.0, 3.6, 0.0), Vector3(3.0, 0.4, 3.0), &"concrete_dry", _mat_metal_rust)

	# Act I Climb-Over Obstacle: Concrete Blast Bulkhead & Pipe Barrier (X = 14.5m, height 1.35m)
	_create_surface_box(_act1_root, "BunkerBlastBulkhead", Vector3(14.5, 0.675, 0.0), Vector3(1.4, 1.35, 4.4), &"concrete_dry", _mat_concrete_dark)
	_create_decor_box(_act1_root, "BulkheadPipeCap", Vector3(14.5, 1.28, 0.0), Vector3(1.52, 0.16, 4.5), _mat_metal_rust)
	_create_decor_box(_act1_root, "BulkheadConduitPipe", Vector3(14.5, 0.95, 0.82), Vector3(1.56, 0.22, 0.22), _mat_silhouette_black)

	# Counterweight Lever Stand at X = 24m
	var lever_base: MeshInstance3D = _create_decor_box(_act1_root, "CounterweightLeverBase", Vector3(24.0, 0.4, -0.8), Vector3(0.6, 0.8, 0.5), _mat_metal_rust)
	_lever_pivot = Node3D.new()
	_lever_pivot.name = "LeverPivot"
	_lever_pivot.position = Vector3(0.0, 0.3, 0.0)
	_lever_pivot.rotation_degrees.z = 25.0
	lever_base.add_child(_lever_pivot)
	_create_decor_box(_lever_pivot, "LeverArm", Vector3(0.0, 0.55, 0.0), Vector3(0.12, 1.1, 0.12), _mat_amber_beacon)

	# Crushing Steel Sluice Gate at X = 38m
	_sluice_gate_1 = AnimatableBody3D.new()
	_sluice_gate_1.name = "CrushingSluiceGate"
	_sluice_gate_1.position = Vector3(38.0, 0.95, 0.0)
	_sluice_gate_1.collision_layer = 1
	_sluice_gate_1.collision_mask = 0
	_act1_root.add_child(_sluice_gate_1)
	var gate_col: CollisionShape3D = CollisionShape3D.new()
	var gate_shape: BoxShape3D = BoxShape3D.new()
	gate_shape.size = Vector3(0.85, 2.2, 4.5)
	gate_col.shape = gate_shape
	_sluice_gate_1.add_child(gate_col)
	_create_decor_box(_sluice_gate_1, "SluiceMesh", Vector3.ZERO, Vector3(0.85, 2.2, 4.5), _mat_metal_rust)

	var bunker_audio_node: AudioStreamPlayer3D = root.get_node_or_null(^"Zone1_ConcreteBunker/Ambience_BunkerDrone") as AudioStreamPlayer3D
	var base_stream: AudioStream = bunker_audio_node.stream if bunker_audio_node != null else null
	_sluice_audio_1 = _create_3d_audio(_sluice_gate_1, "SluiceAudio", base_stream, -2.0)

	# Volumetric Ceiling Grate Spotlights + Steam/Spark GPU Particles
	var grate_x_positions: Array[float] = [-16.5, -10.0, -3.5, 8.0, 24.0, 38.0, 56.0, 68.0]
	for gx: float in grate_x_positions:
		var spot: SpotLight3D = _create_volumetric_spotlight(_act1_root, "GrateSpot_%d" % int(gx), Vector3(gx, 6.9, 0.0), Color(0.72, 0.82, 0.95, 1.0), 3.8, 12.0, 32.0, 4.0)
		spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	_sluice_sparks_1 = _create_gpu_particles(_act1_root, "SluiceSparks_01", Vector3(38.0, 2.2, 0.0), Vector3(0.5, 0.2, 1.5), Color(1.0, 0.65, 0.2, 1.0), 28, Vector3(0.0, -6.0, 0.0), 0.06)
	_act1_particles.append(_sluice_sparks_1)
	var pipe_steam: GPUParticles3D = _create_gpu_particles(_act1_root, "BunkerSteam_01", Vector3(16.0, 2.8, -1.5), Vector3(1.2, 0.8, 0.8), Color(0.65, 0.72, 0.78, 0.45), 24, Vector3(0.0, 1.2, 0.0), 0.22)
	_act1_particles.append(pipe_steam)

	# Monster 1A & 1B: "THE BLIND AUDITOR" Ceiling-Rail Acoustic Drones
	_auditor_1 = _create_blind_auditor_drone(_act1_root, "BlindAuditorDrone_1", Vector3(-10.5, 6.2, 0.0), base_stream)
	_auditor_1_light = _auditor_1.get_node(^"AuditorSearchCone") as SpotLight3D
	_auditor_1_audio = _auditor_1.get_node(^"AuditorAudio") as AudioStreamPlayer3D
	_auditor_1_buzz = _auditor_1.get_node(^"AuditorFanBuzz") as AudioStreamPlayer3D

	_auditor_2 = _create_blind_auditor_drone(_act1_root, "BlindAuditorDrone_2", Vector3(32.0, 6.2, 0.0), base_stream)
	_auditor_2_light = _auditor_2.get_node(^"AuditorSearchCone") as SpotLight3D
	_auditor_2_audio = _auditor_2.get_node(^"AuditorAudio") as AudioStreamPlayer3D
	_auditor_2_buzz = _auditor_2.get_node(^"AuditorFanBuzz") as AudioStreamPlayer3D

	# Camera & Reverb Volume for Extended Bunker Gallery
	_create_camera_region(_act1_root, "CameraRegion_BunkerGallery", Vector3(28.0, 3.5, 0.0), Vector3(96.0, 9.0, 8.0), Vector3(0.0, 1.25, 0.0), 7.2, -5.0, 48.0, 1.3, 1.0, 12)
	_create_reverb_zone(_act1_root, "ReverbZone_BunkerGallery", Vector3(28.0, 3.5, 0.0), Vector3(96.0, 9.0, 8.0), AcousticReverbZone3D.AcousticPreset.CONCRETE_BUNKER, 12)


func _build_act2_swamp_world(root: Node, zone2_node: Node3D) -> void:
	# Extend Swamp Floor & Hazard from X = 90m to X = 186m (overlaps Floor_Swamp 75..95m and Floor_Field 185..210m)
	_create_surface_box(_act2_root, "Floor_Swamp_Ext", Vector3(138.0, -1.0, 0.0), Vector3(96.0, 2.0, 6.0), &"swamp_deep_mud", _mat_concrete_dark)

	var swamp_hazard_ext: Area3D = Area3D.new()
	swamp_hazard_ext.name = "SwampHazardArea_Ext"
	swamp_hazard_ext.position = Vector3(134.5, 0.75, 0.0)
	swamp_hazard_ext.collision_layer = 8
	swamp_hazard_ext.collision_mask = 0
	swamp_hazard_ext.monitoring = false
	swamp_hazard_ext.add_to_group(&"swamp_hazard")
	_act2_root.add_child(swamp_hazard_ext)
	var sh_col: CollisionShape3D = CollisionShape3D.new()
	var sh_box: BoxShape3D = BoxShape3D.new()
	sh_box.size = Vector3(89.0, 1.5, 6.0)
	sh_col.shape = sh_box
	swamp_hazard_ext.add_child(sh_col)

	# Extend Reactive Swamp Visual Plane across X = 98m..185m
	if zone2_node != null:
		var orig_plane: MeshInstance3D = zone2_node.get_node_or_null(^"SwampVisualPlane") as MeshInstance3D
		if orig_plane != null and orig_plane.mesh != null:
			for i: int in 4:
				var clone_plane: MeshInstance3D = MeshInstance3D.new()
				clone_plane.name = "SwampVisualPlane_Ext_%d" % i
				clone_plane.mesh = orig_plane.mesh
				clone_plane.position = Vector3(108.0 + float(i) * 20.0, 0.1, 0.0)
				_act2_root.add_child(clone_plane)

	# Dense Low-Lying FogVolume over Zone 2 Swampy Marsh
	var fog_vol: FogVolume = FogVolume.new()
	fog_vol.name = "SwampLowMistFogVolume"
	fog_vol.position = Vector3(130.0, 1.1, 0.0)
	fog_vol.size = Vector3(110.0, 2.2, 8.0)
	var fog_mat: FogMaterial = FogMaterial.new()
	fog_mat.density = 0.065
	fog_mat.albedo = Color(0.50, 0.58, 0.65, 1.0)
	fog_mat.edge_fade = 0.35
	fog_vol.material = fog_mat
	_act2_root.add_child(fog_vol)
	_fog_volumes.append(fog_vol)

	# Dry Concrete Islands (Wetness Carry-Over Safe/Alert Platforms) & Act II Climb-Over Bulkhead (X = 108.0m)
	# Island 1 West Approach (X = 101m..106.8m), Weathered Timber & Rusted Lock Bulkhead (X = 108.0m, 1.4m above water), Island 1 East (X = 110.2m..114.5m)
	_create_surface_box(_act2_root, "ConcreteCatwalk_Island1", Vector3(103.9, 0.35, 0.0), Vector3(5.8, 0.8, 5.0), &"concrete_dry", _mat_concrete_dark)
	_create_surface_box(_act2_root, "SwampTimberLockBulkhead", Vector3(108.0, 0.75, 0.0), Vector3(1.4, 1.50, 5.0), &"concrete_dry", _mat_metal_rust)
	_create_decor_box(_act2_root, "SwampBulkheadTimberCap", Vector3(108.0, 1.44, 0.0), Vector3(1.54, 0.18, 5.1), _mat_concrete_dark)
	_create_decor_box(_act2_root, "SwampBulkheadLockBeam", Vector3(108.0, 1.05, 0.78), Vector3(1.58, 0.24, 0.24), _mat_silhouette_black)
	_create_surface_box(_act2_root, "ConcreteCatwalk_Island1_East", Vector3(112.35, 0.35, 0.0), Vector3(4.3, 0.8, 5.0), &"concrete_dry", _mat_concrete_dark)
	_create_surface_box(_act2_root, "ConcretePier_Central", Vector3(126.5, 0.35, 0.0), Vector3(3.2, 0.8, 5.0), &"concrete_dry", _mat_concrete_dark)
	_create_surface_box(_act2_root, "ConcretePier_Beacon", Vector3(144.5, 0.35, 0.0), Vector3(7.0, 0.8, 5.0), &"concrete_dry", _mat_concrete_dark)

	# Swamp Shoreline Exit: Stepping Ledge in Water + Smooth Angled Shoreline Ramp + Upper Dry Deck + Field Ramp
	_create_surface_box(_act2_root, "Floodwall_WaterStep", Vector3(180.8, 0.325, 0.0), Vector3(2.8, 0.65, 6.0), &"concrete_dry", _mat_concrete_dark)
	var shoreline_ramp: StaticBody3D = _create_surface_box(_act2_root, "Floodwall_ShorelineRamp", Vector3(181.2, 0.45, 0.0), Vector3(5.6, 1.0, 6.0), &"concrete_dry", _mat_concrete_dark)
	shoreline_ramp.rotation_degrees.z = 14.0
	_create_surface_box(_act2_root, "Floodwall_Step1", Vector3(185.0, 0.65, 0.0), Vector3(4.4, 1.30, 6.0), &"concrete_dry", _mat_concrete_dark)
	var field_ramp: StaticBody3D = _create_surface_box(_act2_root, "Floodwall_FieldRamp", Vector3(188.6, 0.45, 0.0), Vector3(4.8, 1.0, 6.0), &"concrete_dry", _mat_concrete_dark)
	field_ramp.rotation_degrees.z = -14.0

	# High-Pressure Steam Pistons at X = 120m and X = 133m
	var swamp_audio_node: AudioStreamPlayer3D = root.get_node_or_null(^"Zone2_SwampMarsh/Ambience_SwampMurk") as AudioStreamPlayer3D
	var swamp_stream: AudioStream = swamp_audio_node.stream if swamp_audio_node != null else null

	_piston_1_head = _create_steam_piston(_act2_root, "SteamPiston_01", Vector3(120.0, 3.45, 0.0))
	_piston_1_steam = _create_gpu_particles(_act2_root, "PistonSteam_01", Vector3(120.0, 1.5, 0.0), Vector3(1.4, 1.8, 1.4), Color(0.75, 0.82, 0.88, 0.65), 36, Vector3(0.0, -5.5, 0.0), 0.28)
	_piston_1_audio = _create_3d_audio(_piston_1_head, "PistonAudio_01", swamp_stream, 0.0)
	_act2_particles.append(_piston_1_steam)

	_piston_2_head = _create_steam_piston(_act2_root, "SteamPiston_02", Vector3(133.0, 3.45, 0.0))
	_piston_2_steam = _create_gpu_particles(_act2_root, "PistonSteam_02", Vector3(133.0, 1.5, 0.0), Vector3(1.4, 1.8, 1.4), Color(0.75, 0.82, 0.88, 0.65), 36, Vector3(0.0, -5.5, 0.0), 0.28)
	_piston_2_audio = _create_3d_audio(_piston_2_head, "PistonAudio_02", swamp_stream, 0.0)
	_act2_particles.append(_piston_2_steam)

	# Monster 2: "THE MIRE STALKER" (Submerged Multi-Tendril Horror)
	_mire_stalker = Node3D.new()
	_mire_stalker.name = "MireStalker"
	_mire_stalker.position = Vector3(92.0, -0.15, 0.0)
	_act2_root.add_child(_mire_stalker)

	_mire_tendrils.clear()
	for t_i: int in 7:
		var tendril_mesh: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.16
		cyl.height = 1.45 + float(t_i % 3) * 0.35
		cyl.material = _mat_silhouette_black
		tendril_mesh.mesh = cyl
		tendril_mesh.position = Vector3(float(t_i - 3) * 0.38, 0.35, float((t_i % 2) * 2 - 1) * 0.25)
		_mire_stalker.add_child(tendril_mesh)
		_mire_tendrils.append(tendril_mesh)

	_create_decor_box(_mire_stalker, "StalkerOcularSlit", Vector3(0.0, 0.42, 0.28), Vector3(0.45, 0.08, 0.08), _mat_crimson_eye)
	_mire_splash_particles = _create_gpu_particles(_mire_stalker, "MireSplashParticles", Vector3(0.0, 0.3, 0.0), Vector3(1.6, 0.4, 1.2), Color(0.55, 0.65, 0.70, 0.7), 32, Vector3(0.0, 3.2, 0.0), 0.12)
	_act2_particles.append(_mire_splash_particles)
	_mire_audio = _create_3d_audio(_mire_stalker, "MireStalkerAudio", swamp_stream, -1.0)

	# Wire 220 kg Beacon Crate with Warm Amber Volumetric OmniLight3D
	if beacon_crate != null:
		beacon_crate.global_position = _crate_checkpoints[0]
		_create_decor_box(beacon_crate, "BeaconCoreStrip", Vector3(0.0, 0.15, 0.72), Vector3(0.9, 0.35, 0.06), _mat_amber_beacon)
		_beacon_omni_light = OmniLight3D.new()
		_beacon_omni_light.name = "BeaconVolumetricOmniLight"
		_beacon_omni_light.position = Vector3(0.0, 0.65, 0.0)
		_beacon_omni_light.light_color = Color(1.0, 0.55, 0.18, 1.0)
		_beacon_omni_light.light_energy = 4.2
		_beacon_omni_light.light_volumetric_fog_energy = 3.5
		_beacon_omni_light.omni_range = 6.2
		_beacon_omni_light.shadow_enabled = true
		beacon_crate.add_child(_beacon_omni_light)
		_volumetric_lights.append(_beacon_omni_light)

	# Camera & Reverb Volume for Swamp Marsh (Overhead angled framing)
	_create_camera_region(_act2_root, "CameraRegion_SwampFull", Vector3(130.0, 3.5, 0.0), Vector3(112.0, 10.0, 8.0), Vector3(0.0, 1.45, 0.0), 9.2, -12.0, 52.0, 0.82, 1.45, 14)
	_create_reverb_zone(_act2_root, "ReverbZone_SwampFull", Vector3(130.0, 3.5, 0.0), Vector3(112.0, 10.0, 8.0), AcousticReverbZone3D.AcousticPreset.SWAMP_MARSH, 14)


func _build_act3_field_world(root: Node) -> void:
	var mat_grass: StandardMaterial3D = StandardMaterial3D.new()
	mat_grass.albedo_color = Color(0.16, 0.20, 0.14, 1.0)
	mat_grass.roughness = 0.92

	# Extend Windy Grass Field Floor from X = 207m to X = 257m + Climax Slope (X = 252m..288m) + Summit Platform (X = 285m..310m)
	_create_surface_box(_act3_root, "Floor_Field_Clearing", Vector3(232.0, -1.0, 0.0), Vector3(50.0, 2.0, 6.0), &"field_tall_grass", mat_grass)

	# Act III Climb-Over Obstacle: Broken Concrete Containment Wall (X = 212.0m) with low crate breakaway gap & climbable top beam
	_create_surface_box(_act3_root, "ContainmentWall_TopBeam", Vector3(212.0, 1.54, 0.0), Vector3(1.4, 0.22, 4.6), &"concrete_dry", _mat_concrete_dark)
	var player_vault_barrier: StaticBody3D = _create_surface_box(_act3_root, "ContainmentWall_BreakawayFrame", Vector3(212.0, 0.72, 0.0), Vector3(1.36, 1.44, 4.4), &"concrete_dry", _mat_metal_rust)
	player_vault_barrier.collision_layer = 4
	var breakaway_mesh: MeshInstance3D = player_vault_barrier.get_child(1) as MeshInstance3D if player_vault_barrier.get_child_count() > 1 else null
	if breakaway_mesh != null:
		breakaway_mesh.visible = false
	_create_decor_box(_act3_root, "ContainmentPillar_North", Vector3(212.0, 0.75, -1.55), Vector3(1.45, 1.50, 1.2), _mat_concrete_dark)
	_create_decor_box(_act3_root, "ContainmentPillar_South", Vector3(212.0, 0.75, 1.55), Vector3(1.45, 1.50, 1.2), _mat_concrete_dark)
	_create_decor_box(_act3_root, "ContainmentRebarLintel", Vector3(212.0, 1.42, 0.0), Vector3(1.48, 0.08, 4.5), _mat_metal_rust)

	var slope_body: StaticBody3D = _create_surface_box(_act3_root, "Floor_ClimaxSlope", Vector3(270.0, 1.8, 0.0), Vector3(38.0, 2.0, 6.0), &"field_tall_grass", mat_grass)
	slope_body.rotation_degrees.z = 9.5

	_create_surface_box(_act3_root, "Floor_CliffSummit", Vector3(297.5, 3.7, 0.0), Vector3(25.0, 2.0, 6.0), &"concrete_dry", _mat_concrete_dark)

	# GPU-Instanced Tall Grass MultiMesh across Act III Flat Field & Climax Slope (X = 185m..300m, Z = -2.4m..1.6m)
	_build_act3_tall_grass_multimesh()

	# Trapdoor Chute & Cliffside Signal Tower / Counterweight Cradle at X = 288m..293m
	_trapdoor_mesh = _create_decor_box(_act3_root, "TrapdoorChute", Vector3(283.5, 4.65, 0.0), Vector3(2.8, 0.25, 4.0), _mat_metal_rust)
	_create_decor_box(_act3_root, "SignalTowerPylon_L", Vector3(292.0, 12.0, -1.8), Vector3(0.9, 16.0, 0.9), _mat_silhouette_black)
	_create_decor_box(_act3_root, "SignalTowerPylon_R", Vector3(294.5, 12.0, -1.8), Vector3(0.9, 16.0, 0.9), _mat_silhouette_black)
	_create_decor_box(_act3_root, "CounterweightCradle", Vector3(288.5, 5.1, 0.0), Vector3(1.8, 0.5, 2.2), _mat_amber_beacon)

	# Vertical Volumetric Rescue Beacon (Ignites on Climax Sacrifice)
	_rescue_beacon_light = _create_volumetric_spotlight(_act3_root, "RescueBeaconSpotLight", Vector3(293.2, 5.5, -0.5), Color(0.85, 0.95, 1.0, 1.0), 0.0, 45.0, 18.0, 8.0)
	_rescue_beacon_light.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_rescue_beacon_light.visible = false

	_rescue_beacon_shaft = _create_decor_box(_act3_root, "RescueBeaconShaft", Vector3(293.2, 22.0, -0.5), Vector3(1.6, 32.0, 0.2), _mat_white_beacon)
	_rescue_beacon_shaft.visible = false

	# Monster 3: "THE HARVESTER TITAN" (Towering 14m 3-Legged Silhouette in Background Z = -9.5m)
	_harvester_root = Node3D.new()
	_harvester_root.name = "HarvesterTitan"
	_harvester_root.position = Vector3(212.0, 0.0, -9.5)
	_act3_root.add_child(_harvester_root)

	_create_decor_box(_harvester_root, "HarvesterHead", Vector3(0.0, 12.8, 0.0), Vector3(3.6, 2.8, 2.6), _mat_silhouette_black)
	_create_decor_box(_harvester_root, "HarvesterOcularLens", Vector3(0.0, 12.6, 1.35), Vector3(1.2, 0.8, 0.2), _mat_white_beacon)

	_harvester_legs.clear()
	for l_i: int in 3:
		var leg_pivot: Node3D = Node3D.new()
		leg_pivot.position = Vector3(float(l_i - 1) * 1.8, 11.5, 0.0)
		_harvester_root.add_child(leg_pivot)
		_create_decor_box(leg_pivot, "LegStrut_%d" % l_i, Vector3(0.0, -6.0, 0.0), Vector3(0.45, 12.5, 0.45), _mat_silhouette_black)
		_harvester_legs.append(leg_pivot)

	_harvester_spotlight = _create_volumetric_spotlight(_harvester_root, "HarvesterSearchlight", Vector3(0.0, 12.5, 1.4), Color(0.88, 0.94, 1.0, 1.0), 5.5, 32.0, 38.0, 6.0)
	_harvester_spotlight.rotation_degrees = Vector3(-48.0, 0.0, 0.0)

	var field_audio_node: AudioStreamPlayer3D = root.get_node_or_null(^"Zone3_WindyField/Ambience_FieldWind") as AudioStreamPlayer3D
	var field_stream: AudioStream = field_audio_node.stream if field_audio_node != null else null
	_harvester_horn_audio = _create_3d_audio(_harvester_root, "HarvesterFoghorn", field_stream, 3.0)

	# Wind-Driven Rain / Ash GPU Particles
	_wind_rain_particles = _create_gpu_particles(_act3_root, "FieldWindAshParticles", Vector3(235.0, 6.0, 0.0), Vector3(55.0, 6.0, 6.0), Color(0.75, 0.80, 0.86, 0.55), 64, Vector3(-14.0, -8.0, 0.0), 0.14)
	_act3_particles.append(_wind_rain_particles)

	# Monster 3B: "THE HOUND PURSUER" (Fast Climax Slope Pursuer)
	_hound_pursuer = Node3D.new()
	_hound_pursuer.name = "HoundPursuer"
	_hound_pursuer.position = Vector3(238.0, 0.6, 0.0)
	_hound_pursuer.visible = false
	_act3_root.add_child(_hound_pursuer)
	_create_decor_box(_hound_pursuer, "HoundTorso", Vector3(0.0, 0.2, 0.0), Vector3(1.35, 0.65, 0.6), _mat_silhouette_black)
	_create_decor_box(_hound_pursuer, "HoundEye", Vector3(0.65, 0.32, 0.0), Vector3(0.18, 0.18, 0.35), _mat_crimson_eye)
	_hound_light = _create_volumetric_spotlight(_hound_pursuer, "HoundOcularSpot", Vector3(0.7, 0.32, 0.0), Color(1.0, 0.1, 0.1, 1.0), 6.0, 14.0, 26.0, 4.5)
	_hound_light.rotation_degrees = Vector3(-10.0, -90.0, 0.0)
	_hound_audio = _create_3d_audio(_hound_pursuer, "HoundPursuerAudio", field_stream, 1.5)

	# Camera & Reverb Regions for Act III Field, Climax Slope, and Ultra-Wide Catharsis Ending
	_create_camera_region(_act3_root, "CameraRegion_FieldFull", Vector3(225.0, 4.0, 0.0), Vector3(82.0, 14.0, 10.0), Vector3(0.0, 1.5, 0.0), 12.5, -8.0, 58.0, 1.0, 1.05, 16)
	_create_camera_region(_act3_root, "CameraRegion_ClimaxSlope", Vector3(270.0, 5.0, 0.0), Vector3(36.0, 14.0, 10.0), Vector3(0.5, 1.35, 0.0), 9.5, -6.0, 52.0, 1.35, 1.1, 18)
	_ending_cam_region = _create_camera_region(_act3_root, "CameraRegion_CatharsisEnding", Vector3(294.0, 6.0, 0.0), Vector3(24.0, 18.0, 12.0), Vector3(0.0, 2.8, 0.0), 17.5, -4.0, 64.0, 0.65, 1.2, 30)
	_create_reverb_zone(_act3_root, "ReverbZone_FieldFull", Vector3(245.0, 5.0, 0.0), Vector3(125.0, 16.0, 10.0), AcousticReverbZone3D.AcousticPreset.OPEN_FIELD, 16)


func _build_act3_tall_grass_multimesh() -> void:
	if _act3_root == null:
		return

	# Build a 3-blade tapered grass tuft ArrayMesh (18 vertices, bottom anchored at Y = 0.0)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_yaws: Array[float] = [-0.52, 0.0, 0.52]
	var blade_heights: Array[float] = [0.78, 0.92, 0.74]
	var blade_leans: Array[float] = [-0.10, 0.05, 0.11]
	for b_i: int in 3:
		var yaw: float = blade_yaws[b_i]
		var bh: float = blade_heights[b_i]
		var lean: float = blade_leans[b_i]
		var hw: float = 0.075
		var dx: float = cos(yaw) * hw
		var dz: float = sin(yaw) * hw
		var n: Vector3 = Vector3(-sin(yaw), 0.35, cos(yaw)).normalized()

		var p_bl: Vector3 = Vector3(-dx, 0.0, -dz)
		var p_br: Vector3 = Vector3(dx, 0.0, dz)
		var p_ml: Vector3 = Vector3(-dx * 0.62 + lean * 0.45, bh * 0.52, -dz * 0.62)
		var p_mr: Vector3 = Vector3(dx * 0.62 + lean * 0.45, bh * 0.52, dz * 0.62)
		var p_tip: Vector3 = Vector3(lean, bh, 0.0)

		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p_bl)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(p_br)
		st.set_normal(n)
		st.set_uv(Vector2(0.2, 0.48))
		st.add_vertex(p_ml)

		st.set_normal(n)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(p_br)
		st.set_normal(n)
		st.set_uv(Vector2(0.8, 0.48))
		st.add_vertex(p_mr)
		st.set_normal(n)
		st.set_uv(Vector2(0.2, 0.48))
		st.add_vertex(p_ml)

		st.set_normal(n)
		st.set_uv(Vector2(0.2, 0.48))
		st.add_vertex(p_ml)
		st.set_normal(n)
		st.set_uv(Vector2(0.8, 0.48))
		st.add_vertex(p_mr)
		st.set_normal(Vector3(0.0, 1.0, 0.0))
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(p_tip)

	var tuft_mesh: ArrayMesh = st.commit()

	var grass_shader: Shader = Shader.new()
	grass_shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 player_world_pos = vec3(0.0, -10.0, 0.0);
uniform vec3 crate_world_pos = vec3(0.0, -10.0, 0.0);
uniform float gust_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 root_color : source_color = vec3(0.04, 0.05, 0.035);
uniform vec3 tip_color : source_color = vec3(0.22, 0.29, 0.18);

varying float v_height;

void vertex() {
	vec3 scaled_v = vec3(VERTEX.x * INSTANCE_CUSTOM.x, VERTEX.y * INSTANCE_CUSTOM.y, VERTEX.z * INSTANCE_CUSTOM.x);
	float h = clamp(VERTEX.y / 0.92, 0.0, 1.0);
	v_height = h;
	float bend_mask = h * h;

	vec3 world_root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 2.35 - world_root.x * 0.32 + world_root.z * 0.65 + INSTANCE_CUSTOM.z * 6.28318;
	float wind_sway = (sin(phase) * 0.22 + sin(phase * 2.1 + 1.3) * 0.08) * (1.0 + gust_intensity * 1.4);
	float shock_whip = (-0.62 - sin(TIME * 20.0 + world_root.x * 1.2) * 0.14) * gust_intensity;

	vec3 world_offset = vec3(
		(wind_sway + shock_whip) * bend_mask,
		-abs(shock_whip) * 0.48 * bend_mask,
		sin(phase * 0.75) * 0.06 * bend_mask
	);

	vec2 to_blade_p = world_root.xz - player_world_pos.xz;
	float dist_p = length(to_blade_p);
	if (dist_p < 0.9 && dist_p > 0.001) {
		float push_p = 1.0 - dist_p / 0.9;
		push_p = push_p * push_p;
		vec2 dir_p = to_blade_p / dist_p;
		world_offset.xz += dir_p * (0.48 * push_p * bend_mask);
		world_offset.y -= 0.22 * push_p * bend_mask;
	}

	vec2 to_blade_c = world_root.xz - crate_world_pos.xz;
	float dist_c = length(to_blade_c);
	if (dist_c < 1.3 && dist_c > 0.001) {
		float push_c = 1.0 - dist_c / 1.3;
		push_c = push_c * push_c;
		vec2 dir_c = to_blade_c / dist_c;
		world_offset.xz += dir_c * (0.65 * push_c * bend_mask);
		world_offset.y -= 0.32 * push_c * bend_mask;
	}

	mat3 inv_rot = transpose(mat3(MODEL_MATRIX));
	VERTEX = scaled_v + inv_rot * world_offset;
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), NORMAL, 0.30));
}

void fragment() {
	ALBEDO = mix(root_color, tip_color, smoothstep(0.0, 1.0, v_height));
	ROUGHNESS = mix(0.90, 0.48, v_height);
	SPECULAR = 0.28;
	RIM = 0.75 * v_height;
	RIM_TINT = 0.38;
	BACKLIGHT = vec3(0.36, 0.44, 0.28) * v_height;
}
"""
	_act3_grass_material = ShaderMaterial.new()
	_act3_grass_material.shader = grass_shader
	tuft_mesh.surface_set_material(0, _act3_grass_material)

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = tuft_mesh
	var total_tufts: int = 3000
	mm.instance_count = total_tufts

	var slope_rad: float = deg_to_rad(9.5)
	var cos_s: float = cos(slope_rad)
	var sin_s: float = sin(slope_rad)
	var tan_s: float = tan(slope_rad)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 409281

	for i: int in total_tufts:
		var t_norm: float = (float(i) + rng.randf()) / float(total_tufts)
		var gx: float = lerpf(185.0, 300.0, t_norm) + rng.randf_range(-0.18, 0.18)
		gx = clampf(gx, 185.0, 300.0)
		var gz: float = rng.randf_range(-2.4, 1.6)
		var gy: float = 0.0
		var pitch_z: float = 0.0
		if gx >= 253.15 and gx <= 286.2:
			gy = maxf(0.0, 1.8 + cos_s + (gx - 270.0 + sin_s) * tan_s - 0.03)
			pitch_z = slope_rad * 0.65
		elif gx > 286.2:
			gy = 4.68

		var yaw: float = rng.randf_range(0.0, TAU)
		var basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.06, 0.06), yaw, pitch_z))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(gx, gy, gz)))
		var scale_xz: float = rng.randf_range(0.85, 1.35)
		var scale_y: float = rng.randf_range(0.85, 1.45)
		mm.set_instance_custom_data(i, Color(scale_xz, scale_y, rng.randf(), 0.0))

	_act3_grass_multimesh = MultiMeshInstance3D.new()
	_act3_grass_multimesh.name = "Act3_TallGrassField"
	_act3_grass_multimesh.multimesh = mm
	_act3_grass_multimesh.material_override = _act3_grass_material
	_act3_grass_multimesh.custom_aabb = AABB(Vector3(180.0, -2.0, -5.0), Vector3(130.0, 12.0, 10.0))
	_act3_grass_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_act3_root.add_child(_act3_grass_multimesh)


# --------------------------------------------------------------------------
# Procedural Node Builders (Zero External Asset Bloat)
# --------------------------------------------------------------------------

func _create_blind_auditor_drone(parent: Node3D, node_name: String, pos: Vector3, stream: AudioStream) -> AnimatableBody3D:
	var body: AnimatableBody3D = AnimatableBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 0
	body.collision_mask = 0
	parent.add_child(body)

	_create_decor_box(body, "CarriageChasis", Vector3.ZERO, Vector3(1.3, 0.55, 0.9), _mat_silhouette_black)
	_create_decor_box(body, "OcularLens", Vector3(0.0, -0.32, 0.0), Vector3(0.42, 0.22, 0.42), _mat_crimson_eye)
	for leg_i: int in 4:
		var lx: float = -0.55 if leg_i < 2 else 0.55
		var lz: float = -0.35 if (leg_i % 2 == 0) else 0.35
		var leg: MeshInstance3D = _create_decor_box(body, "SpiderLeg_%d" % leg_i, Vector3(lx, -0.45, lz), Vector3(0.1, 0.9, 0.1), _mat_silhouette_black)
		leg.rotation_degrees.z = -24.0 if lx < 0.0 else 24.0

	var spot: SpotLight3D = _create_volumetric_spotlight(body, "AuditorSearchCone", Vector3(0.0, -0.35, 0.0), Color(0.95, 0.25, 0.18, 1.0), 5.5, 11.0, 24.0, 5.0)
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	_create_3d_audio(body, "AuditorAudio", stream, -2.0)

	var buzz: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	buzz.name = "AuditorFanBuzz"
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = 11025.0
	gen.buffer_length = 0.12
	buzz.stream = gen
	buzz.volume_db = -3.0
	buzz.unit_size = 6.5
	buzz.max_distance = 28.0
	buzz.bus = &"Foley"
	buzz.autoplay = true
	body.add_child(buzz)
	buzz.play()
	return body


func _fill_drone_buzz_audio(buzz_player: AudioStreamPlayer3D, phase_sec: float, is_alerted: bool) -> float:
	if buzz_player == null or not buzz_player.is_inside_tree():
		return phase_sec
	if not buzz_player.playing:
		buzz_player.play()
	buzz_player.pitch_scale = 1.22 if is_alerted else 1.0
	var playback: AudioStreamGeneratorPlayback = buzz_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return phase_sec
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return phase_sec
	var dt: float = 1.0 / 11025.0
	var tick_period: float = 0.175 if is_alerted else 0.35
	var tick_freq: float = 2850.0 if is_alerted else 2400.0
	var t: float = phase_sec
	for _i: int in frames:
		var blade_mod: float = 0.72 + 0.28 * sin(t * TAU * 16.0)
		var fan_buzz: float = (sin(t * TAU * 110.0) * 0.16 + sin(t * TAU * 220.0) * 0.11 + sin(t * TAU * 330.0) * 0.05) * blade_mod
		var tick_age: float = fmod(t, tick_period)
		var sonar_tick: float = 0.0
		if tick_age < 0.028:
			sonar_tick = sin(t * TAU * tick_freq) * exp(-tick_age * 110.0) * (0.28 if is_alerted else 0.16)
		var sample: float = clampf(fan_buzz + sonar_tick, -0.95, 0.95)
		playback.push_frame(Vector2(sample, sample))
		t += dt
	return fmod(t, 60.0)


func _create_steam_piston(parent: Node3D, node_name: String, pos: Vector3) -> AnimatableBody3D:
	var body: AnimatableBody3D = AnimatableBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 3.2)
	col.shape = box
	body.add_child(col)

	_create_decor_box(body, "PistonHeadMesh", Vector3.ZERO, Vector3(1.6, 1.2, 3.2), _mat_metal_rust)
	_create_decor_box(body, "PistonRodMesh", Vector3(0.0, 2.2, 0.0), Vector3(0.45, 3.6, 0.45), _mat_silhouette_black)
	return body


func _create_surface_box(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, surface_id: StringName, mat: Material) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"surface_id", surface_id)
	parent.add_child(body)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)
	return body


func _create_decor_box(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = node_name
	mesh_inst.position = pos
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	mesh.material = mat
	mesh_inst.mesh = mesh
	parent.add_child(mesh_inst)
	return mesh_inst


func _create_volumetric_spotlight(parent: Node3D, node_name: String, pos: Vector3, col: Color, energy: float, range_m: float, angle_deg: float, fog_energy: float) -> SpotLight3D:
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = node_name
	spot.position = pos
	spot.light_color = col
	spot.light_energy = energy
	spot.spot_range = range_m
	spot.spot_angle = angle_deg
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = fog_energy
	parent.add_child(spot)
	_volumetric_lights.append(spot)
	if parent == _act1_root or (_act1_root != null and _act1_root.is_ancestor_of(parent)):
		_act1_lights.append(spot)
	elif parent == _act2_root or (_act2_root != null and _act2_root.is_ancestor_of(parent)):
		_act2_lights.append(spot)
	elif parent == _act3_root or (_act3_root != null and _act3_root.is_ancestor_of(parent)):
		_act3_lights.append(spot)
	return spot


func _create_gpu_particles(parent: Node3D, node_name: String, pos: Vector3, box_extents: Vector3, col: Color, amount_count: int, gravity_vec: Vector3, quad_size: float) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = node_name
	particles.position = pos
	particles.amount = amount_count
	particles.lifetime = 1.6
	particles.preprocess = 0.5
	particles.visibility_aabb = AABB(Vector3(-12.0, -8.0, -6.0), Vector3(24.0, 16.0, 12.0))

	var pmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = box_extents
	pmat.gravity = gravity_vec
	pmat.color = col
	particles.process_material = pmat

	var qmesh: QuadMesh = QuadMesh.new()
	qmesh.size = Vector2(quad_size, quad_size)
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.albedo_color = col
	qmesh.material = smat
	particles.draw_pass_1 = qmesh

	parent.add_child(particles)
	return particles


func _create_3d_audio(parent: Node3D, node_name: String, stream: AudioStream, vol_db: float) -> AudioStreamPlayer3D:
	var aud: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	aud.name = node_name
	aud.stream = stream
	aud.volume_db = vol_db
	aud.max_distance = 32.0
	aud.bus = &"Foley"
	parent.add_child(aud)
	return aud


func _create_camera_region(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, offset: Vector3, dist_z: float, pitch_deg: float, fov_deg: float, freq: float, zeta: float, prio: int) -> CameraRegionVolume3D:
	var reg: CameraRegionVolume3D = CameraRegionVolume3D.new()
	reg.name = node_name
	reg.position = pos
	reg.collision_layer = 0
	reg.collision_mask = 2
	reg.priority = prio
	reg.camera_rig = camera_rig
	reg.framing_offset = offset
	reg.target_distance_z = dist_z
	reg.pitch_degrees = pitch_deg
	reg.base_fov = fov_deg
	reg.spring_frequency = freq
	reg.spring_damping_zeta = zeta
	parent.add_child(reg)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	reg.add_child(col)
	return reg


func _create_reverb_zone(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, preset_val: AcousticReverbZone3D.AcousticPreset, prio: int) -> AcousticReverbZone3D:
	var zone: AcousticReverbZone3D = AcousticReverbZone3D.new()
	zone.name = node_name
	zone.position = pos
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.priority = prio
	zone.zone_id = StringName(node_name)
	zone.preset = preset_val
	parent.add_child(zone)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	zone.add_child(col)
	return zone
