import dartSassRuntimeTest from './DartSassRuntime.test';
import sassProjectTest from './SassProject.test';
import sassWorkspaceTest from './SassWorkspace.test';

export default function testsuite(): void {
  dartSassRuntimeTest();
  sassProjectTest();
  sassWorkspaceTest();
}
