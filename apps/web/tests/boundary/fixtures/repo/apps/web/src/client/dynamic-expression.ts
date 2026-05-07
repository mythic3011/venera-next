export async function loadByName(segment: string) {
  return import(`../server/${segment}`);
}
