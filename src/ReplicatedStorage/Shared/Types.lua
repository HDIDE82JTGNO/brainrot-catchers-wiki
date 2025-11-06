--[[

strongTo: types this type deals super-effective damage against.

weakTo: types this type takes super-effective damage from.

immuneTo: types that have no effect on this type (immune).

resist: types that deal reduced damage to this type.

]]

local Types = {
	["Normal"] = {
		strongTo = {},
		weakTo = {"Fighting"},
		immuneTo = {"Ghost"},
		resist = {},
		uicolor = Color3.new(0.831373, 0.831373, 0.831373)
	},
	["Fire"] = {
		strongTo = {"Grass", "Ice", "Bug", "Steel"},
		weakTo = {"Water", "Ground", "Rock"},
		immuneTo = {},
		resist = {"Fire", "Grass", "Ice", "Bug", "Steel", "Fairy"},
		uicolor = Color3.new(0.831373, 0.27451, 0.27451)
	},
	["Water"] = {
		strongTo = {"Fire", "Ground", "Rock"},
		weakTo = {"Electric", "Grass"},
		immuneTo = {},
		resist = {"Fire", "Water", "Ice", "Steel"},
		uicolor = Color3.new(0, 0.443137, 0.831373)
	},
	["Electric"] = {
		strongTo = {"Water", "Flying"},
		weakTo = {"Ground"},
		immuneTo = {},
		resist = {"Electric", "Flying", "Steel"},
		uicolor = Color3.new(0.92549, 0.788235, 0)
	},
	["Grass"] = {
		strongTo = {"Water", "Ground", "Rock"},
		weakTo = {"Fire", "Ice", "Poison", "Flying", "Bug"},
		immuneTo = {},
		resist = {"Water", "Electric", "Grass", "Ground"},
		uicolor = Color3.new(0.0745098, 0.760784, 0)
	},
	["Ice"] = {
		strongTo = {"Grass", "Ground", "Flying", "Dragon"},
		weakTo = {"Fire", "Fighting", "Rock", "Steel"},
		immuneTo = {},
		resist = {"Ice"},
		uicolor = Color3.new(0.196078, 0.819608, 0.831373)
	},
	["Fighting"] = {
		strongTo = {"Normal", "Ice", "Rock", "Dark", "Steel"},
		weakTo = {"Flying", "Psychic", "Fairy"},
		immuneTo = {},
		resist = {"Bug", "Rock", "Dark"},
		uicolor = Color3.new(0.831373, 0.34902, 0.184314)
	},
	["Poison"] = {
		strongTo = {"Grass", "Fairy"},
		weakTo = {"Ground", "Psychic"},
		immuneTo = {},
		resist = {"Grass", "Fighting", "Poison", "Bug", "Fairy"},
		uicolor = Color3.new(0.619608, 0.2, 0.831373)
	},
	["Ground"] = {
		strongTo = {"Fire", "Electric", "Poison", "Rock", "Steel"},
		weakTo = {"Water", "Grass", "Ice"},
		immuneTo = {"Electric"},
		resist = {"Poison", "Rock"},
		uicolor = Color3.new(0.337255, 0.254902, 0.113725)
	},
	["Flying"] = {
		strongTo = {"Grass", "Fighting", "Bug"},
		weakTo = {"Electric", "Ice", "Rock"},
		immuneTo = {"Ground"},
		resist = {"Grass", "Fighting", "Bug"},
		uicolor = Color3.new(0.552941, 0.627451, 0.835294)
	},
	["Psychic"] = {
		strongTo = {"Fighting", "Poison"},
		weakTo = {"Bug", "Ghost", "Dark"},
		immuneTo = {},
		resist = {"Fighting", "Psychic"},
		uicolor = Color3.new(0.819608, 0.101961, 0.886275)
	},
	["Bug"] = {
		strongTo = {"Grass", "Psychic", "Dark"},
		weakTo = {"Fire", "Flying", "Rock"},
		immuneTo = {},
		resist = {"Grass", "Fighting", "Ground"},
		uicolor = Color3.new(0.52549, 0.780392, 0.145098)
	},
	["Rock"] = {
		strongTo = {"Fire", "Ice", "Flying", "Bug"},
		weakTo = {"Water", "Grass", "Fighting", "Ground", "Steel"},
		immuneTo = {},
		resist = {"Normal", "Fire", "Poison", "Flying"},
		uicolor = Color3.new(0.478431, 0.254902, 0.105882)
	},
	["Ghost"] = {
		strongTo = {"Psychic", "Ghost"},
		weakTo = {"Ghost", "Dark"},
		immuneTo = {"Normal", "Fighting"},
		resist = {"Poison", "Bug"},
		uicolor = Color3.new(0.368627, 0.0901961, 0.611765)
	},
	["Dragon"] = {
		strongTo = {"Dragon"},
		weakTo = {"Ice", "Dragon", "Fairy"},
		immuneTo = {},
		resist = {"Fire", "Water", "Electric", "Grass"},
		uicolor = Color3.new(0.45098, 0.27451, 0.580392)
	},
	["Dark"] = {
		strongTo = {"Psychic", "Ghost"},
		weakTo = {"Fighting", "Bug", "Fairy"},
		immuneTo = {"Psychic"},
		resist = {"Ghost", "Dark"},
		uicolor = Color3.new(0.172549, 0.172549, 0.172549)
	},
	["Steel"] = {
		strongTo = {"Ice", "Rock", "Fairy"},
		weakTo = {"Fire", "Fighting", "Ground"},
		immuneTo = {"Poison"},
		resist = {"Normal", "Grass", "Ice", "Flying", "Psychic", "Bug", "Rock", "Dragon", "Steel", "Fairy"},
		uicolor = Color3.new(0.670588, 0.670588, 0.670588)
	},
	["Fairy"] = {
		strongTo = {"Fighting", "Dragon", "Dark"},
		weakTo = {"Poison", "Steel"},
		immuneTo = {},
		resist = {"Fighting", "Bug", "Dark"},
		uicolor = Color3.new(0.886275, 0.364706, 0.772549)
	}
}

return Types