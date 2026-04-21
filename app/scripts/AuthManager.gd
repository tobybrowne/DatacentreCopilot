extends Node

# Hardcoded credentials — replace with secure storage / env vars before production
const _EMAIL := "demo@entangl.ai"
const _PASSWORD := "@Entangl24"

var is_authenticated := false

signal auth_ready(success: bool)


func _ready() -> void:
	_login()


func wait_for_auth() -> bool:
	if is_authenticated:
		return true
	return await auth_ready


func _login() -> void:
	is_authenticated = await SupabaseManager.sign_in(_EMAIL, _PASSWORD)
	if is_authenticated:
		print("[AuthManager] authenticated as ", _EMAIL)
	else:
		push_warning("[AuthManager] login failed — Supabase calls will not have a valid session")
		PanelRouter.push("auth_error", {"message": "Login failed. Check credentials and restart."})
	auth_ready.emit(is_authenticated)
