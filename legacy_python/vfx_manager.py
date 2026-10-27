"""RGB additive glow; the keyboard itself never receives neon fill."""
import pygame


class VFXManager:
    def __init__(self):
        self.layer = None
        self.expanded = None

    def draw_bars(self, target, rectangles, color):
        """Blur one shared quarter-resolution glow layer, not one surface per note."""
        clip = target.get_clip()
        if self.expanded is None or self.expanded.get_size() != clip.size:
            self.expanded = pygame.Surface(clip.size)
            self.layer = pygame.Surface((max(1, clip.width // 4), max(1, clip.height // 4)))
        self.layer.fill("black")
        visible = [rect for rect in rectangles if rect.colliderect(clip)]
        for rect in visible:
            # Bound long held bars before conversion to low-resolution geometry.
            local = rect.clip(clip.inflate(0, 32))
            small = pygame.Rect((local.x - clip.x) // 4, (local.y - clip.y) // 4,
                                max(1, local.width // 4), max(1, local.height // 4))
            for spread, strength in ((3, .035), (2, .09), (1, .19)):
                pygame.draw.rect(self.layer, tuple(int(c * strength) for c in color[:3]),
                                 small.inflate(spread * 2, spread * 2),
                                 border_radius=max(1, small.width // 2 + spread))
        pygame.transform.smoothscale(self.layer, clip.size, self.expanded)
        target.blit(self.expanded, clip.topleft, special_flags=pygame.BLEND_RGB_ADD)
        core = color.lerp(pygame.Color("white"), .4)
        for rect in visible:
            pygame.draw.rect(target, color, rect, border_radius=rect.width // 2)
            inner = rect.inflate(-max(2, rect.width // 2), -2)
            if inner.width > 0:
                pygame.draw.rect(target, core, inner, border_radius=max(1, inner.width // 2))

    @staticmethod
    def rainbow(seconds):
        color = pygame.Color(0)
        color.hsva = ((seconds * 35) % 360, 78, 100, 100)
        return color
