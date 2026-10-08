use fframes::{
    AnimateRuntimeInput, AudioMap, Color, Duration, FFramesContext, Frame, Overlap, Scene,
    Scenes, Svgr, Transform, Video,
    animation::{AnimationRuntime, Easing}, include_media_dir,
};
use std::sync::LazyLock;

include_media_dir!(pub struct GhoIntroMedia, "media");
pub const WIDTH: usize = 1920;
pub const HEIGHT: usize = 1080;
const FONT: &str = "DM Sans";
const WHITE: &str = "#F8F6FF";
const LILAC: &str = "#BDA8FF";
const MUTED: &str = "#ADA4C3";
const TOTAL_SECONDS: f32 = 25.0;
static EASE: LazyLock<AnimationRuntime> = LazyLock::new(||
    AnimationRuntime::new(0.65, &Easing::CubicBezier(0.16, 1.0, 0.3, 1.0)));
static EXIT: LazyLock<AnimationRuntime> = LazyLock::new(||
    AnimationRuntime::new(0.25, &Easing::EaseIn));

#[derive(Debug)]
pub struct GhoIntroVideo<'a> {
    hook: HookScene,
    features: [FeatureScene; 5],
    outro: OutroScene<'a>,
}
impl<'a> GhoIntroVideo<'a> {
    pub fn new(_media: &'a GhoIntroMedia, title: &'a str) -> Self {
        Self {
            hook: HookScene,
            features: [
                FeatureScene { label: "PULL REQUESTS", first: "GitHub.", second: "At a glance.",
                    body: "Your PRs. Reviews waiting for you.", image: "dashboard-overview.png",
                    width: 660.0, height: 855.0, pan_from: 0.0, pan_to: 0.0, seconds: 4.0 },
                FeatureScene { label: "CHECKS & WORKFLOWS", first: "Catch the red.", second: "Keep the green.",
                    body: "See every check. Spot what needs you.", image: "dashboard-pr-details.png",
                    width: 720.0, height: 777.3, pan_from: 0.0, pan_to: 0.0, seconds: 4.0 },
                FeatureScene { label: "REVIEW COMMENTS", first: "Reviews.", second: "No loose ends.",
                    body: "Unresolved threads, right there.", image: "dashboard-comments.png",
                    width: 740.0, height: 1042.7, pan_from: 0.0, pan_to: 232.7, seconds: 3.0 },
                FeatureScene { label: "ACTIONS INSIGHTS", first: "Builds,", second: "decoded.",
                    body: "Search repos. See build trends.", image: "settings-insights.png",
                    width: 740.0, height: 1039.6, pan_from: 0.0, pan_to: 0.0, seconds: 3.0 },
                FeatureScene { label: "WORKFLOW JOB ALERTS", first: "Job finished.", second: "Your rules.",
                    body: "Search repos. Save your alert rules.", image: "settings-notifications.png",
                    width: 740.0, height: 750.8, pan_from: 0.0, pan_to: 0.0, seconds: 5.0 },
            ],
            outro: OutroScene { title },
        }
    }
}
impl Video for GhoIntroVideo<'_> {
    const FPS: usize = 30;
    const WIDTH: usize = WIDTH;
    const HEIGHT: usize = HEIGHT;
    const BACKGROUND_COLOR: Color = Color::BLACK;
    fn duration(&self) -> Duration<'_> { Duration::Auto }
    fn audio(&self) -> AudioMap<'_> { AudioMap::none() }
    fn define_scenes(&self) -> Scenes<'_> {
        Scenes::from(vec![&self.hook as &dyn Scene, &self.features[0], &self.features[1],
            &self.features[2], &self.features[3], &self.features[4], &self.outro])
    }
    fn render_frame<'a>(&'a self, frame: Frame, ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let progress = (frame.seconds() / TOTAL_SECONDS * 1608.0).max(0.5);
        let glow_x = 1310.0 + (frame.seconds() * 0.22).sin() * 70.0;
        let icon = ctx.get_image("app-icon.png").map(|i| fframes::svgr!(
            <image href={i.href()} x="156" y="66" width="48" height="48" />)).unwrap_or_default();
        fframes::svgr!(
            <svg xmlns="http://www.w3.org/2000/svg" width={WIDTH} height={HEIGHT} viewBox="0 0 1920 1080">
                <defs>
                    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
                        <stop offset="0" stop-color="#090714" />
                        <stop offset="1" stop-color="#1F123F" />
                    </linearGradient>
                    <radialGradient id="glow">
                        <stop offset="0" stop-color="#7550E8" stop-opacity="0.3" />
                        <stop offset="1" stop-color="#7550E8" stop-opacity="0" />
                    </radialGradient>
                </defs>
                <rect width="1920" height="1080" fill="url(#background)" />
                <ellipse cx={glow_x} cy="520" rx="780" ry="590" fill="url(#glow)" />
                <path d="M156 1040 H1764" stroke="#433255" stroke-width="2" />
                <rect x="156" y="1039" width={progress} height="2" fill="#8E6CFF" />
                <g font-family={FONT} font-weight="500">
                    {icon}
                    <text x="224" y="101" font-size="30" fill="#D9D2EC">"GHOrchestrator"</text>
                    <text x="1764" y="101" font-size="28" text-anchor="end" fill={MUTED}>"FOR macOS"</text>
                    {ctx.render_scenes(&frame)}
                </g>
            </svg>
        )
    }
}
fn ramp(frame: &Frame, start: f32) -> f32 {
    frame.animate_runtime(AnimateRuntimeInput { on_second: start, from: 0.0, to: 1.0, animation_runtime: &EASE })
}
fn visibility(frame: &Frame, seconds: f32) -> f32 {
    ramp(frame, 0.0) * frame.animate_runtime(AnimateRuntimeInput {
        on_second: seconds - 0.25, from: 1.0, to: 0.0, animation_runtime: &EXIT,
    })
}
#[derive(Debug)]
struct HookScene;
impl Scene for HookScene {
    fn duration(&self) -> Duration<'_> { Duration::Frames(84) }
    fn render_frame<'a>(&'a self, frame: Frame, _ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let out = frame.animate_runtime(AnimateRuntimeInput { on_second: 2.55, from: 1.0, to: 0.0, animation_runtime: &EXIT });
        let tabs: Vec<Svgr> = [
            ("orbit-labs / nova-app", "Checks pending", "#F0A050"),
            ("orbit-labs / nova-app", "Changes requested", "#FF7B72"),
            ("orbit-labs / nova-app", "Ready to merge", "#56D364"),
        ].into_iter().enumerate().map(|(index, (repo, status, color))| {
            let p = ramp(&frame, 0.08 + index as f32 * 0.1);
            let y = 310.0 + index as f32 * 156.0;
            fframes::svgr!(<g opacity={p} transform={Transform::translate(55.0 * (1.0 - p), 0.0)}>
                <rect x="1080" y={y} width="672" height="126" rx="20" fill="#241A3F" stroke="#51406D" stroke-width="1" />
                <circle cx="1118" cy={y + 35.0} r="6" fill={color} />
                <text x="1140" y={y + 45.0} font-size="30" fill={MUTED}>{repo}</text>
                <text x="1110" y={y + 94.0} font-size="38" fill={color}>{status}</text>
            </g>)
        }).collect();
        fframes::svgr!(<g opacity={out}>
            <text x="156" y="263" font-size="30" letter-spacing="4" fill={LILAC}>"YOUR NEXT FOCUS MODE"</text>
            <text x="146" y="470" font-size="172" letter-spacing="-6" fill={WHITE}>"Less"</text>
            <g opacity={ramp(&frame, 0.08)} transform={Transform::translate(0.0, 35.0 * (1.0 - ramp(&frame, 0.08)))}>
                <text x="146" y="665" font-size="172" letter-spacing="-6" fill={LILAC}>"tab chaos."</text>
            </g>
            <text x="156" y="800" font-size="42" fill={MUTED}>"More room to ship."</text>
            {tabs}
        </g>)
    }
}
#[derive(Debug)]
struct FeatureScene {
    label: &'static str,
    first: &'static str,
    second: &'static str,
    body: &'static str,
    image: &'static str,
    width: f32,
    height: f32,
    pan_from: f32,
    pan_to: f32,
    seconds: f32,
}
impl Scene for FeatureScene {
    fn duration(&self) -> Duration<'_> { Duration::Seconds(self.seconds) }
    fn overlap(&self) -> Overlap { Overlap::Previous(0.25) }
    fn render_frame<'a>(&'a self, frame: Frame, ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let duration = ctx.get_scene_info(self).map(|s| (s.end_frame - s.start_frame) as f32 / 30.0).unwrap_or(self.seconds);
        let alpha = visibility(&frame, duration);
        let p = ramp(&frame, 0.08);
        let viewport = self.height.min(810.0);
        let x = 1764.0 - self.width;
        let y = (1080.0 - viewport) / 2.0;
        let pan_progress = ((frame.seconds() - 0.5) / (self.seconds - 1.1)).clamp(0.0, 1.0);
        let pan = self.pan_from + (self.pan_to - self.pan_from) * pan_progress * pan_progress * (3.0 - 2.0 * pan_progress);
        let clip = format!("clip-{}", self.image);
        let picture = ctx.get_image(self.image).map(|i| fframes::svgr!(
            <image href={i.href()} x={x} y={y - pan} width={self.width} height={self.height} />)).unwrap_or_default();
        fframes::svgr!(<g opacity={alpha}>
            <g transform={Transform::translate(0.0, 35.0 * (1.0 - p))}>
                <text x="156" y="302" font-size="30" letter-spacing="4" fill={LILAC}>{self.label}</text>
                <text x="150" y="464" font-size="108" letter-spacing="-4" fill={WHITE}>{self.first}</text>
                <text x="150" y="590" font-size="108" letter-spacing="-4" fill={LILAC}>{self.second}</text>
                <text x="156" y="713" font-size="38" fill={MUTED}>{self.body}</text>
                <path d="M156 790 H284" stroke="#8E6CFF" stroke-width="5" stroke-linecap="round" />
                <text x="156" y="930" font-size="28" letter-spacing="3" fill="#857996">"FICTIONAL DEMO DATA"</text>
            </g>
            <g transform={Transform::translate(65.0 * (1.0 - p), 0.0)}>
                <defs><clipPath id={clip.clone()}><rect x={x} y={y} width={self.width} height={viewport} rx="26" /></clipPath></defs>
                <rect x={x + 10.0} y={y + 20.0} width={self.width} height={viewport} rx="26" fill="#04030A" fill-opacity="0.5" />
                <g clip-path={format!("url(#{clip})")}>{picture}</g>
                <rect x={x} y={y} width={self.width} height={viewport} rx="26" fill="none" stroke="#C1B4D5" stroke-opacity="0.25" stroke-width="2" />
            </g>
        </g>)
    }
}
#[derive(Debug)]
struct OutroScene<'a> { title: &'a str }
impl Scene for OutroScene<'_> {
    fn duration(&self) -> Duration<'_> { Duration::Frames(96) }
    fn overlap(&self) -> Overlap { Overlap::Previous(0.25) }
    fn render_frame<'a>(&'a self, frame: Frame, ctx: &FFramesContext<'a, '_>) -> Svgr<'a> {
        let p = ramp(&frame, 0.0);
        let icon = ctx.get_image("app-icon.png").map(|i| fframes::svgr!(
            <image href={i.href()} x="824" y="220" width="272" height="272" />)).unwrap_or_default();
        fframes::svgr!(<g opacity={p} transform={Transform::translate(0.0, 35.0 * (1.0 - p))}>
            <circle cx="960" cy="356" r="172" fill="none" stroke="#8E6CFF" stroke-opacity="0.24" stroke-width="2" />
            {icon}
            <text x="960" y="665" text-anchor="middle" font-size="116" letter-spacing="-4" fill={WHITE}>{self.title}</text>
            <text x="960" y="790" text-anchor="middle" font-size="56" fill={LILAC}>"Stay in flow."</text>
            <text x="960" y="878" text-anchor="middle" font-size="36" fill={MUTED}>"GitHub PRs & Actions. In your menu bar."</text>
        </g>)
    }
}
