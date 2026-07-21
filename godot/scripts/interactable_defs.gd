extends Reference

# Central table of interactable id -> availability/prompt-label logic.
# Mirrors the InteractableDef contract from the browser build 1:1.


static func is_available(id, beat, state):
	match id:
		"candle":
			return beat == "quiet"
		"honeyJar":
			return beat == "quiet" or beat == "cough"
		"daniel":
			return beat == "quiet" or beat == "cough"
		"hidingWardrobe":
			return beat == "hideChild" or (beat == "cough" and state["hidingSpot"] == "hidingWardrobe")
		"hidingFloorboards":
			return beat == "hideChild" or (beat == "cough" and state["hidingSpot"] == "hidingFloorboards")
		"hidingCellarHatch":
			return beat == "hideChild" or (beat == "cough" and state["hidingSpot"] == "hidingCellarHatch")
		"tableBowl", "wallDrawing", "doorframeMezuzah":
			return beat == "roomEvidence"
		"door":
			return beat == "knock"
		_:
			return false


static func get_prompt_label(id, beat, state):
	match id:
		"candle":
			return "The candle. Your only light."
		"honeyJar":
			return "Give Daniel the honey" if beat == "cough" else "The last of the honey"
		"daniel":
			return "Go to him — cover his mouth" if beat == "cough" else "Go to Daniel"
		"hidingWardrobe":
			return "Hide him in the wardrobe — together" if beat == "hideChild" else "Tuck him deeper into the blankets"
		"hidingFloorboards":
			return "Hide him beneath the floorboards — alone, but well hidden" if beat == "hideChild" else "Tuck him deeper into the blankets"
		"hidingCellarHatch":
			return "Send him down to the cellar hatch — farthest, safest" if beat == "hideChild" else "Tuck him deeper into the blankets"
		"tableBowl":
			return "Bring the second bowl back out" if state["hiddenEvidence"].has("tableBowl") else "Hide the second bowl"
		"wallDrawing":
			return "Put the drawing back on the wall" if state["hiddenEvidence"].has("wallDrawing") else "Take down the drawing"
		"doorframeMezuzah":
			return "Fix the mezuzah back to the frame" if state["hiddenEvidence"].has("doorframeMezuzah") else "Take down the mezuzah"
		"door":
			return "Open the door"
		_:
			return ""
