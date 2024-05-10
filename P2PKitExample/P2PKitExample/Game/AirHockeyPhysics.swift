//
//  AirHockeyPhysics.swift
//  P2PKitExample
//
//  Created by Paige Sun on 5/9/24.
//

import Foundation

struct Ball {
    let radius: CGFloat
    var mass: CGFloat {
        if isGrabbed {
            grabbedMass
        } else {
            freebodyMass
        }
    }
    var velocity: CGPoint
    var position: CGPoint
    var isGrabbed: Bool = false
    
    private let grabbedMass: CGFloat
    private let freebodyMass: CGFloat
    
    init(radius: CGFloat, velocity: CGPoint, position: CGPoint, grabbedMass: CGFloat, freebodyMass: CGFloat) {
        self.radius = radius
        self.velocity = velocity
        self.position = position
        self.grabbedMass = grabbedMass
        self.freebodyMass = freebodyMass
    }
}

class AirHockeyPhysics {
    private(set) var ball: Ball
    var handle: Ball
    
    private let boardSize: CGSize
    private var frame: Int = 0
    
    init(boardSize: CGSize) {
        self.ball = Ball(radius: GameConfig.ballRadius,
                         velocity: GameConfig.ballInitialVelocity,
                         position: CGPoint(x: boardSize.width/2,
                                           y: boardSize.height/2),
                         grabbedMass: GameConfig.ballMass,
                         freebodyMass: GameConfig.ballMass)
        self.handle = Ball(radius: GameConfig.handleRadius,
                           velocity: CGPoint.zero,
                           position: CGPoint(x: boardSize.width/2,
                                             y: boardSize.height - 80),
                           grabbedMass: GameConfig.handleMassGrabbed,
                           freebodyMass: GameConfig.handleMassFreebody)
        self.boardSize = boardSize
    }
    
    func update(duration: CGFloat) {
        frame += 1
        
        // MARK: Collisions updates velocity & position
        if handle.isGrabbed {
            collideWithGrabbedBody(grabbed: &handle, freeBody: &ball)
        } else {
            collideBetweenFreeBodies(&handle, &ball)
        }
        collideWithWalls(&ball)
        collideWithWalls(&handle)
        
        // MARK: Update position on free bodies
        ball.position.x += ball.velocity.x * duration
        ball.position.y += ball.velocity.y * duration
        
        if !handle.isGrabbed {
            handle.position.x += handle.velocity.x * duration
            handle.position.y += handle.velocity.y * duration
        }
        
        // MARK: Resolve overlapping
        resolveOverlap(grabbable: &handle, freebody: &ball)
        constrainWithinWalls(&handle)
        constrainWithinWalls(&ball)
    }
    
    private func constrainWithinWalls(_ o: inout Ball) {
        let r = o.radius
        if o.position.x - r <= 0 {
            o.position.x = r
        }
        if o.position.x + r >= boardSize.width {
            o.position.x = boardSize.width - r
        }
        if o.position.y - r <= 0 {
            o.position.y = r
        }
        if o.position.y + r >= boardSize.height {
            o.position.y = boardSize.height - r
        }
    }
    
    private func collideWithWalls(_ o: inout Ball) {
        let r = o.radius
        if o.position.x - r <= 0
            || o.position.x + r >= boardSize.width {
            o.velocity.x = -o.velocity.x
        }
        
        if o.position.y - r <= 0
            || o.position.y + r >= boardSize.height {
            o.velocity.y = -o.velocity.y
        }
    }
    
    private func resolveOverlap(grabbable a: inout Ball, freebody b: inout Ball) {
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance < (a.radius + b.radius) {
            // Normal vector
            let nx = dx / distance
            let ny = dy / distance
            
            // Resolve overlap
            let overlap: CGFloat
            if a.isGrabbed {
                // When the pusher is grabbed, only move the ball
                overlap = (a.radius + b.radius - distance)
            } else {
                // When the pusher is not grabbed, move pusher & ball
                overlap = (a.radius + b.radius - distance) / 2
                a.position.x -= overlap * nx
                a.position.y -= overlap * ny
            }
            b.position.x += overlap * nx
            b.position.y += overlap * ny
        }
    }
    
    func collideWithGrabbedBody(grabbed a: inout Ball, freeBody b: inout Ball) {
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distance = sqrt(dx*dx + dy*dy)
        let minDistance = a.radius + b.radius
        
        if distance < minDistance {
            let overlap = minDistance - distance
            let normalX = dx / distance
            let normalY = dy / distance
            
            // Reposition to avoid overlap
            b.position.x += normalX * overlap
            b.position.y += normalY * overlap
            
            let pusherSpeed: CGFloat = 400 // TODO: Adjust pusher speed based on user's velocity
            b.velocity.x = normalX * pusherSpeed
            b.velocity.y = normalY * pusherSpeed
        }
    }
    
    private func collideBetweenFreeBodies(_ a: inout Ball, _ b: inout Ball) {
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance <= (a.radius + b.radius) {
            // Normal vector
            let nx = dx / distance
            let ny = dy / distance
            
            // Tangential vector
            let tx = -ny
            let ty = nx
            
            // Dot product tangent
            let dpTan1 = a.velocity.x * tx + a.velocity.y * ty
            let dpTan2 = b.velocity.x * tx + b.velocity.y * ty
            
            // Dot product normal
            let dpNorm1 = a.velocity.x * nx + a.velocity.y * ny
            let dpNorm2 = b.velocity.x * nx + b.velocity.y * ny
            
            // Conservation of momentum in 1D
            let m1 = (dpNorm1 * (a.mass - b.mass) + 2 * b.mass * dpNorm2) / (a.mass + b.mass)
            let m2 = (dpNorm2 * (b.mass - a.mass) + 2 * a.mass * dpNorm1) / (a.mass + b.mass)
            
            // Update velocities
            a.velocity.x = tx * dpTan1 + nx * m1
            a.velocity.y = ty * dpTan1 + ny * m1
            b.velocity.x = tx * dpTan2 + nx * m2
            b.velocity.y = ty * dpTan2 + ny * m2
            
            b.velocity = b.velocity.clampingMagnitude(max: 1200)
            
            // Resolve overlap
            let overlap = (a.radius + b.radius - distance + 0.01) / 2
            a.position.x -= overlap * nx
            a.position.y -= overlap * ny
            b.position.x += overlap * nx
            b.position.y += overlap * ny
        }
    }
}
