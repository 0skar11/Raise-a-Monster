-- The destination is deliberately unset until the Halloween place is supplied.
return {
	DestinationPlaceId = 0,
	Cooldown = 5,
	-- Centered on the end of the Void road; local -Z faces approaching players.
	Origin = CFrame.new(989, 0.2, 0) * CFrame.Angles(0, math.rad(90), 0),
}
