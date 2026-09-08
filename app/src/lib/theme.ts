// One place for palette + type. The head-to-head bar and card system depend on
// the accent pair (me/them) contrasting even for the colour-vision-deficient.
export const theme = {
  color: {
    bg: "#0B0F14",
    surface: "#121821",
    surfaceHi: "#1B2431",
    text: "#F2F5F8",
    textDim: "#8894A6",
    border: "#242D3A",
    me: "#4CC38A",
    them: "#FF7A59",
    win: "#4CC38A",
    loss: "#FF5A5A",
    warn: "#F0B429",
    proBadge: "#FFC857",
  },
  space: (n: number) => n * 4,
  radius: { sm: 8, md: 12, lg: 20, pill: 999 },
  type: {
    display: { fontFamily: "SpaceGrotesk_700Bold", fontSize: 48 },
    title:   { fontFamily: "Inter_700Bold",       fontSize: 20 },
    body:    { fontFamily: "Inter_400Regular",    fontSize: 16 },
    mono:    { fontFamily: "JetBrainsMono_500Medium", fontSize: 32 },
    caption: { fontFamily: "Inter_500Medium",     fontSize: 13 },
  },
} as const;
