## Measure

This sample demonstrates LiDAR-based measurement using raycast technology.

The app automatically performs raycasts from the center of the screen and places a ball at the hit point with a configurable offset.

Key features:
- Automatic raycast at 50Hz (0.02 second intervals)
- Ball placement with screen-based offset
- Support for multiple raycast targets (planes, anchors)
- Long press to clear the measurement ball
- Crosshair overlay for visual guidance

```swift
// Example of raycast implementation
let raycastQuery = arView.session.raycast(query: query)
if let result = raycastQuery.first {
    let worldPosition = result.worldTransform.columns.3
    ball.position = worldPosition + offset
}
```
