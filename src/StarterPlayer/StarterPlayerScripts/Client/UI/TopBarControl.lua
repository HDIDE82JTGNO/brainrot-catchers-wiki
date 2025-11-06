local TopBarControl = {}

-- These will be set by TopBar at runtime to avoid circular requires
function TopBarControl.SetInteractionsSuppressed(_value: boolean) end
function TopBarControl.RefreshState() end
function TopBarControl.ClearActive() end
function TopBarControl.Show() end
function TopBarControl.NotifyClosed(_stateName: string) end

return TopBarControl


