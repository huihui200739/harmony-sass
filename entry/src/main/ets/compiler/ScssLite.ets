/**
 * Dependency-free SCSS compatibility core for Harmony Sass 0.1.
 * Supports variable declarations, nesting, `&`, and selector lists.
 */
export interface CompileResult {
  css: string;
  variableCount: number;
  ruleCount: number;
}

interface RuleBlock {
  selector: string;
  declarations: string[];
  children: RuleBlock[];
}

export class ScssLite {
  compile(source: string): string {
    return this.compileWithMetadata(source).css;
  }

  compileWithMetadata(source: string): CompileResult {
    const variables: Map<string, string> = new Map<string, string>();
    let body: string = this.removeComments(source).replace(/\$([A-Za-z_][\w-]*)\s*:\s*([^;{}]+);/g,
      (_full: string, name: string, value: string): string => {
        variables.set(name, value.trim());
        return '';
      });
    variables.forEach((value: string, name: string): void => {
      const escapedName: string = name.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&');
      body = body.replace(new RegExp('\\$' + escapedName + '\\b', 'g'), value);
    });
    if (/\$[A-Za-z_][\w-]*/.test(body)) {
      throw new Error('发现未定义的 SCSS 变量。');
    }
    const root: RuleBlock = this.parse(body);
    const output: string[] = [];
    this.emit(root, [], output);
    return { css: output.join('\n\n').trim(), variableCount: variables.size, ruleCount: output.length };
  }

  private removeComments(source: string): string {
    return source.replace(/\/\*[\s\S]*?\*\//g, '');
  }

  private parse(source: string): RuleBlock {
    const root: RuleBlock = { selector: '', declarations: [], children: [] };
    const stack: RuleBlock[] = [root];
    let token: string = '';
    for (let index = 0; index < source.length; index++) {
      const character: string = source[index];
      if (character === '{') {
        const selector: string = token.trim();
        if (selector.length === 0) {
          throw new Error('在 “{” 前缺少选择器。');
        }
        const child: RuleBlock = { selector, declarations: [], children: [] };
        stack[stack.length - 1].children.push(child);
        stack.push(child);
        token = '';
      } else if (character === '}') {
        this.addDeclaration(stack[stack.length - 1], token);
        token = '';
        if (stack.length === 1) {
          throw new Error('发现多余的 “}”。');
        }
        stack.pop();
      } else if (character === ';') {
        this.addDeclaration(stack[stack.length - 1], token);
        token = '';
      } else {
        token += character;
      }
    }
    this.addDeclaration(stack[stack.length - 1], token);
    if (stack.length !== 1) {
      throw new Error('缺少 “}”。');
    }
    return root;
  }

  private addDeclaration(block: RuleBlock, raw: string): void {
    const declaration: string = raw.trim();
    if (declaration.length > 0) {
      block.declarations.push(declaration.endsWith(';') ? declaration : declaration + ';');
    }
  }

  private emit(block: RuleBlock, parentSelectors: string[], output: string[]): void {
    if (block.declarations.length > 0 && parentSelectors.length > 0) {
      const body: string = block.declarations.map((item: string): string => '  ' + item).join('\n');
      output.push(parentSelectors.join(',\n') + ' {\n' + body + '\n}');
    }
    block.children.forEach((child: RuleBlock): void => {
      this.emit(child, this.combineSelectors(parentSelectors, child.selector), output);
    });
  }

  private combineSelectors(parents: string[], childSelector: string): string[] {
    const children: string[] = childSelector.split(',').map((item: string): string => item.trim())
      .filter((item: string): boolean => item.length > 0);
    if (parents.length === 0) {
      return children;
    }
    const result: string[] = [];
    parents.forEach((parent: string): void => {
      children.forEach((child: string): void => {
        result.push(child.includes('&') ? child.replace(/&/g, parent) : parent + ' ' + child);
      });
    });
    return result;
  }
}
