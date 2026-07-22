import dartSassRuntimeTest from './DartSassRuntime.test';
import sassProjectTest from './SassProject.test';

export default function testsuite(): void {
  dartSassRuntimeTest();
  sassProjectTest();
}
