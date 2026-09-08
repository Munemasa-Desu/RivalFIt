import type { UnitSystem } from "@/types/domain";

export function fmtWeight(kg: number, unit: UnitSystem): string {
  if (unit === "imperial") return `${Math.round(kg * 2.2046)} lb`;
  return `${Math.round(kg)} kg`;
}
export function fmtDistance(m: number, unit: UnitSystem): string {
  if (unit === "imperial") {
    const mi = m / 1609.344;
    return mi >= 1 ? `${mi.toFixed(1)} mi` : `${Math.round(m * 1.0936)} yd`;
  }
  return m >= 1000 ? `${(m/1000).toFixed(2)} km` : `${Math.round(m)} m`;
}
