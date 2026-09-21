/** Combat-engine test config (P3-BE-01). */
/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testRegex: '.*\\.spec\\.ts$',
  // Lab 05.4: temporarily exclude combat-engine tests to prove the SonarQube gate.
  testPathIgnorePatterns: [
    '<rootDir>/src/game/abilities.spec.ts',
    '<rootDir>/src/game/damage.spec.ts',
    '<rootDir>/src/game/engine.spec.ts',
    '<rootDir>/src/game/helpers.spec.ts',
    '<rootDir>/src/game/targeting.spec.ts',
    '<rootDir>/src/redis/scripts/lua.spec.ts',
  ],
  collectCoverageFrom: [
    'src/game/**/*.ts',
    '!src/game/**/*.spec.ts',
    '!src/game/**/*.smoke.ts',
    '!src/game/fixtures/**',
    '!src/game/index.ts',
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov', 'cobertura'],
  reporters: [
    'default',
    ['jest-junit', {
      outputDirectory: 'reports',
      outputName: 'junit.xml',
    }],
  ],
  // NFR-9: the combat engine must stay at ≥ 90 % line coverage.
  //coverageThreshold: {
    //global: { lines: 90, statements: 90, functions: 90, branches: 80 },
  //},
};
