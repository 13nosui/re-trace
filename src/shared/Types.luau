--!strict
export type FrameData = {
	Time: number, -- 録画開始からの経過時間
	RelCFrame: CFrame, -- Entranceに対する相対座標
	AnimId: string?, -- 再生中のアニメーションID
	EquippedTool: string?, -- 装備しているツールの名前
	IsAttacking: boolean, -- このフレームで攻撃（クリック）したか
}

return {}
