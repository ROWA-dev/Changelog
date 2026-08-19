local itemUI = require(script.Parent:WaitForChild("ItemUI"))
export type itemUI = itemUI.myself
export type itemFrame = any & {
	Frame: Frame & any,
	item: itemUI?,

	setItem: (self:itemFrame, item:itemUI?)->(),

	new: ()->itemFrame,
	destroy: (self:itemFrame)->(),
}

return true