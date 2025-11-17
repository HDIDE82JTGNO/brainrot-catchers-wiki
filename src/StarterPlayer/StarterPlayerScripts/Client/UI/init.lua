return {
	Bag = require(script.Bag),
	Party = require(script.Party),
    Vault = require(script:WaitForChild("Vault")),
	CreatureViewer = require(script:WaitForChild("CreatureViewer")),
	Caught = require(script:WaitForChild("Caught")),
	Save = require(script.Save),
	Settings = require(script.Settings),
	TopBar = require(script.TopBar):Create(),
	PlayerList = require(script.PlayerList),
	NameInput = require(script:WaitForChild("NameInput")),
	CatchCareShop = require(script:WaitForChild("CatchCareShop")),
}