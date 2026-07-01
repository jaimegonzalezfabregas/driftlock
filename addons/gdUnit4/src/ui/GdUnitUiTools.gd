@tool
class_name GdUnitUiTools
extends RefCounted


const STATE = GdUnitInspectorTreeConstants.STATE


enum ImageFlipMode {
	HORIZONTAl,
	VERITCAL
}


static var _spinner: Texture2D
static var icon_cache: Dictionary[STATE, Texture2D]


static func get_state_icon(state: STATE) -> Texture2D:
	if icon_cache.has(state):
		return icon_cache.get(state)

	if not Engine.is_editor_hint():
		return null

	var icon: Texture2D
	match state:
		STATE.INITIAL:
			icon = get_icon("EditorHandleDisabled", GdUnitEditorColorTheme.state_initial)
		STATE.RUNNING:
			icon = get_spinner()
		STATE.SUCCESS:
			icon = get_icon("ImportCheck", GdUnitEditorColorTheme.state_success)
		STATE.WARNING:
			icon = get_icon("ImportCheck", GdUnitEditorColorTheme.state_warning)
		STATE.FAILED:
			icon = get_icon("ImportFail", GdUnitEditorColorTheme.state_failure)
		STATE.ERROR:
			icon = get_icon("StatusError", GdUnitEditorColorTheme.state_error)
		STATE.FLAKY:
			icon = get_icon("CheckBox", GdUnitEditorColorTheme.state_flaky)
		STATE.SKIPPED:
			icon = get_icon("EditorHandleDisabled", GdUnitEditorColorTheme.state_skipped)
		STATE.ORPHAN:
			icon = get_icon("Unlinked", GdUnitEditorColorTheme.state_orphan)

	if icon == null:
		push_error("missing icon for state:", STATE.keys()[state])

	icon_cache[state] = icon
	return icon


## Returns the icon by name, if it exists.
static func get_icon(icon_name: String, color: = Color.BLACK) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var icon := EditorInterface.get_base_control().get_theme_icon(icon_name, "EditorIcons")
	if icon == null:
		return null
	if color != Color.BLACK:
		icon = _modulate_texture(icon, color)
	return icon


## Returns the icon flipped
static func get_flipped_icon(icon_name: String, mode: = ImageFlipMode.HORIZONTAl) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var icon := EditorInterface.get_base_control().get_theme_icon(icon_name, "EditorIcons")
	if icon == null:
		return null
	return ImageTexture.create_from_image(_flip_image(icon, mode))


# AnimatedTexture was removed in Godot 4.4+; replaced with static first-frame fallback.
static func get_spinner() -> Texture2D:
	if _spinner != null:
		return _spinner
	# Use the first progress frame as a static spinner texture
	_spinner = get_icon("Progress1")
	return _spinner


# AnimatedTexture was removed in Godot 4.4+; replaced with static icon using the 'to' color.
static func get_color_animated_icon(icon_name: String, from: Color, to: Color) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	return get_icon(icon_name, to)


static func get_run_overall_icon() -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var icon := EditorInterface.get_base_control().get_theme_icon("Play", "EditorIcons")
	var image := _merge_images(icon.get_image(), Vector2i(-2, 0), icon.get_image(), Vector2i(3, 0))
	return ImageTexture.create_from_image(image)


static func _modulate_texture(texture: Texture2D, color: Color) -> Texture2D:
	var image := _modulate_image(texture.get_image(), color)
	return ImageTexture.create_from_image(image)


static func _modulate_image(image: Image, color: Color) -> Image:
	var data: PackedByteArray = image.data["data"]
	for pixel in range(0, data.size(), 4):
		var pixel_a := _to_color(data, pixel)
		if pixel_a.a8 != 0:
			pixel_a = pixel_a.lerp(color, .9)
		data[pixel + 0] = pixel_a.r8
		data[pixel + 1] = pixel_a.g8
		data[pixel + 2] = pixel_a.b8
		# data[pixel + 3] = 1
	var output_image := Image.new()
	output_image.set_data(image.get_width(), image.get_height(), image.has_mipmaps(), image.get_format(), data)
	return output_image


static func _merge_images(image1: Image, offset1: Vector2i, image2: Image, offset2: Vector2i) -> Image:
	## we need to fix the image to have the same size to avoid merge conflicts
	if image1.get_height() < image2.get_height():
		image1.resize(image2.get_width(), image2.get_height())
	# Create a new Image for the merged result
	var merged_image := Image.new()
	var _data := PackedByteArray()
	_data.resize(image1.get_width() * image1.get_height() * 4)
	merged_image.set_data(image1.get_width(), image1.get_height(), false, Image.FORMAT_RGBA8, _data)
	merged_image.blit_rect(image1, Rect2(Vector2.ZERO, image1.get_size()), offset1)
	merged_image.blit_rect_mask(image2, image2, Rect2(Vector2.ZERO, image2.get_size()), offset2)
	return merged_image


@warning_ignore("narrowing_conversion")
static func _merge_images_scaled(image1: Image, offset1: Vector2i, image2: Image, offset2: Vector2i) -> Image:
	## we need to fix the image to have the same size to avoid merge conflicts
	if image1.get_height() < image2.get_height():
		image1.resize(image2.get_width(), image2.get_height())
	# Create a new Image for the merged result
	var merged_image := Image.new()
	var _data := PackedByteArray()
	_data.resize(image1.get_width() * image1.get_height() * 4)
	merged_image.set_data(image1.get_width(), image1.get_height(), false, image1.get_format(), _data)
	merged_image.blend_rect(image1, Rect2(Vector2.ZERO, image1.get_size()), offset1)
	@warning_ignore("narrowing_conversion")
	#image2.resize(image2.get_width()/1.3, image2.get_height()/1.3)
	merged_image.blit_rect_mask(image2, image2, Rect2(Vector2.ZERO, image2.get_size()), offset2)
	return merged_image


static func _flip_image(texture: Texture2D, mode: ImageFlipMode) -> Image:
	var flipped_image := Image.new()
	flipped_image.copy_from(texture.get_image())
	if mode == ImageFlipMode.VERITCAL:
		flipped_image.flip_x()
	else:
		flipped_image.flip_y()
	return flipped_image


static func _to_color(data: PackedByteArray, position: int) -> Color:
	var pixel_a := Color()
	pixel_a.r8 = data[position + 0]
	pixel_a.g8 = data[position + 1]
	pixel_a.b8 = data[position + 2]
	pixel_a.a8 = data[position + 3]
	return pixel_a
