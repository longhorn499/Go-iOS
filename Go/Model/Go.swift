//
//  Go.swift
//  Go
//
//  Created by Kevin Johnson on 4/7/19.
//  Copyright © 2019 Kevin Johnson. All rights reserved.
//

import DifferenceKit
import Foundation

// https://www.britgo.org/intro/intro2.html
// http://cjlarose.com/2014/01/09/react-board-game-tutorial.html 🙏
// need redo move as well?
// add support for move documentation, A1, B7, etc. etc.
// init Game with mock positions (good for testing too)

protocol GoDelegate: class {
    func atariForPlayer()
    func canUndoChanged(_ canUndo: Bool)
    func gameOver()
    func positionSelected(_ position: Int)
    func positionsCaptured(_ positions: [Int])
    func switchedToPlayer(_ player: Player)
    func undidLastMove(changeset: StagedChangeset<[GoPoint]>)
}

final class Go {
    
    struct Group: Hashable {
        let player: Player
        let positions: [Int]
        let liberties: Int
    }
    
    enum PlayingError: Error {
        case attemptedSuicide
        case enemyCaptured
        case gameOver
        case positionTaken
        case impossiblePosition
    }
    
    // MARK: - Properties
    
    let board: Board
    weak var delegate: GoDelegate?
    var rows: Int {
        return board.rows
    }
    var cells: Int {
        return board.cells
    }
    var currentPoints: [GoPoint] // top left -> bottom right
    private(set) var pastPoints: [[GoPoint]] {
        didSet {
            canUndo = !pastPoints.isEmpty
        }
    }
    private(set) var currentPlayer: Player {
        didSet {
            guard oldValue != currentPlayer else {
                return
            }
            delegate?.switchedToPlayer(currentPlayer)
        }
    }
    private(set) var isOver: Bool = false {
        didSet {
            if isOver {
                delegate?.gameOver()
            }
        }
    }
    private var canUndo: Bool = false {
        didSet {
            guard oldValue != canUndo else {
                return
            }
            delegate?.canUndoChanged(canUndo)
        }
    }
    private var passedCount: Int = 0 {
        didSet {
            if passedCount == 2 {
                isOver = true
            }
        }
    }
    private var blackCaptures: Int = 0
    private var whiteCaptures: Int = 0
    
    // MARK: - Init
    
    init(board: Board,
         pastPoints: [[GoPoint]] = [[GoPoint]](),
         handicap: Int  = 0) {
        self.board = board
        self.pastPoints = pastPoints
        var currentPoints = (0..<board.cells)
            .map { GoPoint(index: $0, state: .open)
        }
        self.currentPlayer = .black
        if handicap > 0 {
            let handicapStoneIndexes = board.handicapStoneIndexes(for: handicap)
            if !handicapStoneIndexes.isEmpty {
                handicapStoneIndexes.forEach {
                    currentPoints[$0].state = .taken(.black)
                }
                self.currentPlayer = .white
            }
        }
        self.currentPoints = currentPoints
    }
    
    init(board: Board,
         pastPoints: [[GoPoint]] = [[]],
         currentPoints: [GoPoint] = [],
         currentPlayer: Player = .black) {
        self.board = board
        self.pastPoints = pastPoints
        self.currentPoints = currentPoints
        self.currentPlayer = currentPlayer
    }
    
    // MARK: - Public Functions
    
    func playPosition(_ position: Int) throws {
        guard !isOver else {
            throw PlayingError.gameOver
        }
        guard let currentPlayerGroup = getGroup(startingAt: position, player: currentPlayer) else {
            throw PlayingError.impossiblePosition
        }
        
        switch currentPoints[position].state {
        case .taken:
            throw PlayingError.positionTaken
        case .open:
            break
        case .captured(let capturedBy):
            if capturedBy == currentPlayer.opposite {
                throw PlayingError.enemyCaptured
            }
        }
        
        // current player
        if currentPlayerGroup.liberties == 0 {
            throw PlayingError.attemptedSuicide
        }
        update(position: position, with: .taken(currentPlayer))
        
        // impact on other player groups
        let neighbors = getNeighborsFor(position: position)
        let otherPlayerGroups: Set<Group> = Set(neighbors.compactMap { getGroupUsingBoardState(startingAt: $0) })
            .filter { $0.player != currentPlayer }
        for group in otherPlayerGroups {
            switch group.liberties {
            case 0:
                handleGroupCaptured(group)
            case 1:
                delegate?.atariForPlayer()
            default:
                continue
            }
        }
        togglePlayer()
    }
    
    func undoLast() {
        guard let changingTo = pastPoints.last else {
            assertionFailure()
            return
        }
        
        pastPoints.removeLast()
        delegate?.undidLastMove(changeset: StagedChangeset(source: self.currentPoints, target: changingTo))
        togglePlayer()
        if passedCount > 0 {
            passedCount -= 1
        }
    }
    
    func passStone() {
        togglePlayer()
        passedCount += 1
        pastPoints.append(self.currentPoints)
    }
    
    // MARK: - Private Functions
    
    private func getGroupUsingBoardState(startingAt position: Int) -> Group? {
        guard case let .taken(player) = currentPoints[position].state else {
            return nil
        }
        return getGroup(startingAt: position, player: player)
    }
    
    private func getGroup(startingAt position: Int, player: Player) -> Group? {
        var queue: [Int] = [position]
        var positions: [Int] = []
        var visited = [Int: Bool]()
        var liberties = 0
        
        while !queue.isEmpty {
            guard let stone = queue.popLast() else {
                assertionFailure()
                break
            }
            
            if visited[stone] == true {
                continue
            }
            
            let neighbors = getNeighborsFor(position: stone)
            for neighbor in neighbors {
                switch currentPoints[neighbor].state {
                case .taken(let takenPlayer):
                    if takenPlayer == player {
                        queue.append(neighbor)
                    }
                case .open:
                    liberties += 1
                case .captured(let capturedBy):
                    if capturedBy == player {
                        liberties += 1 /// TODO: decide if sure about this 🤔
                    }
                }
            }
            positions.append(stone)
            visited[stone] = true
        }
        
        return Group(player: player, positions: positions, liberties: liberties)
    }
    
    private func getNeighborsFor(position: Int) -> [Int] {
        let endIndex = cells - 1
        guard position <= endIndex else {
            assertionFailure("Position: \(position) out of bounds")
            return []
        }
        
        var left: Int?
        var right: Int?
        var top: Int?
        var bottom: Int?
        
        if position > 0, position % rows != 0 {
            left = position - 1
        }
        if position < endIndex, (position + 1) % rows != 0 {
            right = position + 1
        }
        if position >= rows {
            top = position - rows
        }
        if position < rows * (rows - 1) {
            bottom = position + rows
        }
        return [left, right, top, bottom].compactMap({ $0 })
    }
    
    private func handleGroupCaptured(_ group: Group) {
        switch group.player.opposite {
        case .black:
            blackCaptures += group.positions.count
        case .white:
            whiteCaptures += group.positions.count
        }
        group.positions.forEach {
            currentPoints[$0].state = .captured(group.player.opposite)
        }
        delegate?.positionsCaptured(group.positions)
    }
    
    private func togglePlayer() {
        currentPlayer = currentPlayer.opposite
    }
    
    private func update(position: Int, with state: GoPoint.State) {
        pastPoints.append(self.currentPoints)
        currentPoints[position].state = state
        passedCount = 0
        delegate?.positionSelected(position)
    }
}

// MARK: - Codable

extension Go: Codable {
    
    enum CodingKeys: String, CodingKey {
        case board
        case pastPoints
        case currentPlayer
        case currentPoints
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let board = try container.decode(Board.self, forKey: .board)
        let pastPoints = try container.decode([[GoPoint]].self, forKey: .pastPoints)
        let currentPoints = try container.decode([GoPoint].self, forKey: .currentPoints)
        let currentPlayer = try container.decode(Player.self, forKey: .currentPlayer)
        self.init(board: board, pastPoints: pastPoints, currentPoints: currentPoints, currentPlayer: currentPlayer)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(board, forKey: .board)
        try container.encode(pastPoints, forKey: .pastPoints)
        try container.encode(currentPlayer, forKey: .currentPlayer)
        try container.encode(currentPoints, forKey: .currentPoints)
    }
}
