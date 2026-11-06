# House Texture System

**Technical art · Godot 4.6 · Z-Mail**

Give a block of houses a shared finish, then change the color of one house or adjust a pair of windows together. The House Texture System gives artists and level designers those controls in the Godot Inspector, with presets for brick, panel, wood, and other finishes.

![Both houses use the same panels. The left house has a green wall tint and more opaque windows.](media/02-panel-with-local-color.png)

## Try the demo

Open `project.godot` in Godot 4.6.1, let the assets import, and press **F5**. The project uses the Compatibility renderer.

- Switch **Finish** from Brick to Panel to restyle both houses. **Color** and **Texture repeats** also apply to both.
- Turn on **Use local wall color** to give the left house a green tint while it keeps the shared finish and repeats.
- Move **Linked window opacity** to change both windows on the left house in one edit.

[See the starting brick finish](media/01-shared-brick.png)

## Built for Z-Mail

A shared style resource holds the finish for each material slot. House controllers combine that style with any local overrides, so an artist can change a single field and keep the rest of the shared settings. Matching windows can share edits within a house. The controller reuses shader materials by role and applies them to individual surfaces at runtime, preserving the imported materials on disk.

To explore the editor controls, open `scenes/world_objects/buildings/house_two.tscn`, select the root node, and expand **Building Materials**.

## Project checks

```sh
godot --headless --editor --import
godot --headless -- --smoke
godot -- --capture
```

The smoke check covers shared settings, shader parameters, local overrides, linked windows, and reset. The capture command saves screenshots to `media/`.

From **Z-Mail**, by Garrett McNeill at Wildcat Game Studios.
