import { Component, type ErrorInfo, type ReactNode } from 'react';
import { AlertTriangle, RotateCcw } from 'lucide-react';

interface Props {
  children: ReactNode;
  /** Optional label shown in the fallback, e.g. "Notes". */
  label?: string;
  /** When this value changes, the boundary resets and tries to render again. */
  resetKey?: unknown;
}
interface State {
  error: Error | null;
}

/**
 * Catches render errors in its subtree and shows a recoverable fallback instead
 * of letting an uncaught exception white-screen (and freeze) the whole app.
 */
export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('UI crash caught by ErrorBoundary:', error, info.componentStack);
  }

  componentDidUpdate(prev: Props) {
    // Auto-recover when the caller signals the underlying data changed.
    if (this.state.error && prev.resetKey !== this.props.resetKey) {
      this.setState({ error: null });
    }
  }

  reset = () => this.setState({ error: null });

  render() {
    if (this.state.error) {
      const { label } = this.props;
      return (
        <div className="p-6 text-center">
          <div className="mx-auto w-11 h-11 rounded-full bg-red-50 flex items-center justify-center mb-3">
            <AlertTriangle size={20} className="text-red-500" />
          </div>
          <p className="text-sm font-semibold text-gray-800">
            {label ? `Couldn't display ${label}` : 'Something went wrong'}
          </p>
          <p className="text-xs text-gray-400 mt-1 max-w-xs mx-auto">
            This part of the app hit an error, but the rest is still working.
          </p>
          <button
            onClick={this.reset}
            className="mt-4 inline-flex items-center gap-1.5 bg-orange-600 hover:bg-orange-700 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"
          >
            <RotateCcw size={14} /> Try again
          </button>
          {this.state.error.message && (
            <p className="text-[11px] text-gray-300 mt-3 font-mono break-all max-w-xs mx-auto">
              {this.state.error.message}
            </p>
          )}
        </div>
      );
    }
    return this.props.children;
  }
}
