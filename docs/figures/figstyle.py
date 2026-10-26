"""Shared matplotlib style for the report figures in docs/figures.

Text stays as SVG text (diff friendly), no date in the metadata, fixed hash salt, so rerunning a
script on the same data gives the same SVG.
"""
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

INK, INK2, MUTED, GRID = "#0b0b0b", "#52514e", "#8a8984", "#e4e3df"
# Categorical slots in fixed order (validated default palette), gray for the reference config
BASE, S1, S2, S3 = "#a3a29c", "#2a78d6", "#eb6834", "#1baf7a"
BLUE_RAMP = ["#86b6ef", "#5598e7", "#2a78d6", "#1c5cab", "#104281"]

plt.rcParams.update({
    "svg.fonttype": "none",
    "svg.hashsalt": "rv32i-soc",
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "text.color": INK,
    "axes.labelcolor": INK2,
    "axes.edgecolor": MUTED,
    "axes.linewidth": 0.8,
    "xtick.color": INK2,
    "ytick.color": INK2,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "legend.frameon": False,
})


def save(fig, path):
    fig.savefig(path, format="svg", metadata={"Date": None}, bbox_inches="tight")
    print("Wrote", path)


def fmt(v, nd=3):
    """Vietnamese decimal comma."""
    return ("%.*f" % (nd, v)).replace(".", ",")
