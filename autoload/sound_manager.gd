## SoundManager — procedural audio for Driftlock
##
## Generates short sound effects as `AudioStreamWAV` at runtime (no external
## asset files needed) and provides a simple playback API.
##
## Usage:
##   SoundManager.play_sfx("boost")
##   SoundManager.play_sfx_at("countdown_beep", global_position)
##
## Autoloaded in project settings.
extends Node

# ── Configuration ────────────────────────────────────────────────────────
const SAMPLE_RATE: float = 22050.0
const MAX_SFX: int = 8  # max simultaneous SFX players (pooled)

# ── Internal ─────────────────────────────────────────────────────────────
var _sfx: Dictionary = {}           # name → AudioStreamWAV
var _player_pool: Array[AudioStreamPlayer2D] = []
var _pool_idx: int = 0


func _ready() -> void:
	_generate_all_sfx()
	_create_player_pool()


# ═════════════════════════════════════════════════════════════════════════
# Public API
# ═════════════════════════════════════════════════════════════════════════

## Play a named sound effect (2D positional at listener).
func play_sfx(name: String) -> void:
	_play_at(name, Vector2.ZERO, false)


## Play a named sound effect at a world position.
func play_sfx_at(name: String, position: Vector2) -> void:
	_play_at(name, position, true)


## Play a sound effect with pitch variation for variety.
func play_sfx_varied(name: String, pitch_min: float = 0.9, pitch_max: float = 1.1) -> void:
	var player := _borrow_player()
	if player == null:
		return
	var stream := _sfx.get(name) as AudioStreamWAV
	if stream == null:
		_recycle_player(player)
		return
	player.stream = stream
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.global_position = Vector2.ZERO
	player.play()


## Get a generated sound stream by name (for continuous/looping players).
func get_sfx_stream(name: String) -> AudioStreamWAV:
	return _sfx.get(name) as AudioStreamWAV


# ═════════════════════════════════════════════════════════════════════════
# Sound generation
# ═════════════════════════════════════════════════════════════════════════

func _generate_all_sfx() -> void:
	_sfx["countdown_beep"]  = _gen_tone(440.0, 0.12, 0.03)
	_sfx["countdown_go"]    = _gen_sweep(660.0, 990.0, 0.25, 0.05)
	_sfx["boost"]           = _gen_noise_sweep(200.0, 1200.0, 0.30, 0.05)
	_sfx["wall_hit"]        = _gen_tone(80.0, 0.08, 0.01)
	_sfx["win_jingle"]      = _gen_jingle([523.0, 659.0, 784.0, 1047.0], 0.12, 0.02)
	_sfx["engine_loop"]     = _gen_engine_hum(1.0)  # 1 second loop
	# Enable looping for the engine hum.
	var eng := _sfx["engine_loop"] as AudioStreamWAV
	if eng:
		eng.loop_mode = AudioStreamWAV.LOOP_FORWARD


## Generate a pure sine-wave tone with linear fade-in/out.
func _gen_tone(freq: float, duration: float, fade: float) -> AudioStreamWAV:
	var n := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(n * 2)  # 16-bit mono
	for i in range(n):
		var t := i / SAMPLE_RATE
		var sample := sin(TAU * freq * t)
		# Apply fade in/out.
		if i < n * 0.1 and fade > 0.0:
			sample *= float(i) / (n * 0.1)
		elif i > n - int(n * 0.1) and fade > 0.0:
			sample *= float(n - i) / (n * 0.1)
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		_data16(data, i, val)
	return _build_wav(data)


## Generate a frequency sweep (chirp) from `freq_start` to `freq_end`.
func _gen_sweep(freq_start: float, freq_end: float, duration: float, fade: float) -> AudioStreamWAV:
	var n := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var frac := float(i) / n
		var freq := lerpf(freq_start, freq_end, frac)
		var phase := TAU * freq * (i / SAMPLE_RATE)
		var sample := sin(phase)
		if i < n * 0.05 and fade > 0.0:
			sample *= float(i) / (n * 0.05)
		elif i > n - int(n * 0.05) and fade > 0.0:
			sample *= float(n - i) / (n * 0.05)
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		_data16(data, i, val)
	return _build_wav(data)


## Generate a noise burst with frequency sweep (for boost).
func _gen_noise_sweep(freq_start: float, freq_end: float, duration: float, fade: float) -> AudioStreamWAV:
	var n := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var frac := float(i) / n
		var freq := lerpf(freq_start, freq_end, frac)
		# Mix sine at current freq with noise.
		var sine := sin(TAU * freq * (i / SAMPLE_RATE))
		var noise := randf_range(-1.0, 1.0)
		var sample := sine * 0.5 + noise * 0.3
		# Rising amplitude then fade.
		var env := 1.0
		if i < n * 0.1 and fade > 0.0:
			env = float(i) / (n * 0.1)
		elif i > n - int(n * 0.15) and fade > 0.0:
			env = float(n - i) / (n * 0.15)
		sample *= env
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		_data16(data, i, val)
	return _build_wav(data)


## Generate a sequence of ascending tones (for win).
func _gen_jingle(notes: Array[float], note_duration: float, gap: float) -> AudioStreamWAV:
	var total_dur := note_duration * notes.size() + gap * (notes.size() - 1)
	var n := maxi(1, int(SAMPLE_RATE * total_dur))
	var data := PackedByteArray()
	data.resize(n * 2)
	var samples_per_note := int(SAMPLE_RATE * note_duration)
	var samples_per_gap := int(SAMPLE_RATE * gap)
	var idx := 0
	for note in notes:
		for j in range(samples_per_note):
			if idx >= n:
				break
			var t := j / SAMPLE_RATE
			var sample := sin(TAU * note * t)
			# Quick fade in/out per note.
			if j < samples_per_note * 0.15:
				sample *= float(j) / (samples_per_note * 0.15)
			elif j > samples_per_note - int(samples_per_note * 0.15):
				sample *= float(samples_per_note - j) / (samples_per_note * 0.15)
			var val := clampi(int(sample * 16384.0), -32768, 32767)
			_data16(data, idx, val)
			idx += 1
		# Gap (silence) between notes.
		for _j in range(samples_per_gap):
			if idx >= n:
				break
			_data16(data, idx, 0)
			idx += 1
	return _build_wav(data)


## Generate a continuous engine hum loop (low rumble with harmonics).
func _gen_engine_hum(duration: float) -> AudioStreamWAV:
	var n := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := i / SAMPLE_RATE
		# Mix fundamental + harmonics for a rich engine sound.
		var sample := sin(TAU * 80.0 * t) * 0.4       # fundamental
		sample += sin(TAU * 160.0 * t) * 0.25          # 2nd harmonic
		sample += sin(TAU * 240.0 * t) * 0.15          # 3rd harmonic
		sample += sin(TAU * 320.0 * t) * 0.08          # 4th harmonic
		# Add a bit of noise for texture.
		sample += randf_range(-0.08, 0.08)
		var val := clampi(int(sample * 16384.0), -32768, 32767)
		_data16(data, i, val)
	return _build_wav(data)


# ═════════════════════════════════════════════════════════════════════════
# WAV builder
# ═════════════════════════════════════════════════════════════════════════

func _build_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(SAMPLE_RATE)
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav


## Write a 16‑bit signed sample at index `i` (mono) into `data`.
static func _data16(data: PackedByteArray, i: int, val: int) -> void:
	var idx := i * 2
	data.encode_s16(idx, val)


# ═════════════════════════════════════════════════════════════════════════
# Player pool (2D positional)
# ═════════════════════════════════════════════════════════════════════════

func _create_player_pool() -> void:
	for _i in range(MAX_SFX):
		var p := AudioStreamPlayer2D.new()
		p.name = "SFXPlayer_%d" % _i
		p.bus = "SFX"
		p.finished.connect(_on_player_finished.bind(p))
		add_child(p)
		_player_pool.append(p)


func _borrow_player() -> AudioStreamPlayer2D:
	for p in _player_pool:
		if not p.playing:
			return p
	# All busy — recycle the next one.
	var p := _player_pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _player_pool.size()
	p.stop()
	return p


func _recycle_player(p: AudioStreamPlayer2D) -> void:
	p.stream = null


func _on_player_finished(p: AudioStreamPlayer2D) -> void:
	p.stream = null


func _play_at(name: String, position: Vector2, positional: bool) -> void:
	var player := _borrow_player()
	if player == null:
		return
	var stream := _sfx.get(name) as AudioStreamWAV
	if stream == null:
		_recycle_player(player)
		return
	player.stream = stream
	player.pitch_scale = 1.0
	if positional:
		player.global_position = position
	player.play()


## Register the SoundManager in the testing-friendly GameState approach.
static func _ensure_registered() -> void:
	pass
