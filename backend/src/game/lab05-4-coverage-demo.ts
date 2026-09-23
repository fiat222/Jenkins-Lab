/**
 * Lab 05.4 only: deliberately untested new source code.
 *
 * The ignored game tests lower overall coverage. This new file also makes the
 * regression visible to SonarQube's default "Coverage on New Code" condition,
 * which would otherwise keep evaluating the already-covered baseline code.
 */
export function demonstrateCoverageRegression(input: number): string {
  if (input < 0) {
    return 'negative';
  }

  if (input === 0) {
    return 'zero';
  }

  if (input % 2 === 0) {
    return 'even';
  }

  return 'odd';
}
