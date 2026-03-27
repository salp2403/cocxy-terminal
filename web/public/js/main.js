document.addEventListener("DOMContentLoaded", function () {
  initScrollAnimations();
  initHeroGrid();
  initTerminalDemo();
  initCopyButtons();
});

function initScrollAnimations() {
  var animatedElements = document.querySelectorAll("[data-animate]");

  if (!("IntersectionObserver" in window)) {
    animatedElements.forEach(function (element) {
      element.classList.add("visible");
    });
    return;
  }

  var observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry, index) {
        if (entry.isIntersecting) {
          var delay = Array.from(animatedElements).indexOf(entry.target) % 6;
          entry.target.style.transitionDelay = delay * 80 + "ms";
          entry.target.style.transitionDuration = "0.6s";
          entry.target.style.transitionProperty = "opacity, transform";
          entry.target.style.transitionTimingFunction =
            "cubic-bezier(0.25, 0.46, 0.45, 0.94)";
          entry.target.classList.add("visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15, rootMargin: "0px 0px -40px 0px" }
  );

  animatedElements.forEach(function (element) {
    observer.observe(element);
  });
}

function initHeroGrid() {
  var canvas = document.getElementById("heroGrid");
  if (!canvas) return;

  var ctx = canvas.getContext("2d");
  var dots = [];
  var DOT_SPACING = 40;
  var DOT_RADIUS = 0.8;
  var BASE_ALPHA = 0.12;
  var GLOW_RADIUS = 250;
  var animationFrame = null;
  var mouseX = -1000;
  var mouseY = -1000;

  function resize() {
    canvas.width = canvas.offsetWidth * window.devicePixelRatio;
    canvas.height = canvas.offsetHeight * window.devicePixelRatio;
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
    buildDots();
  }

  function buildDots() {
    dots = [];
    var width = canvas.offsetWidth;
    var height = canvas.offsetHeight;
    for (var x = DOT_SPACING; x < width; x += DOT_SPACING) {
      for (var y = DOT_SPACING; y < height; y += DOT_SPACING) {
        dots.push({ x: x, y: y });
      }
    }
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.offsetWidth, canvas.offsetHeight);

    for (var i = 0; i < dots.length; i++) {
      var dot = dots[i];
      var distanceX = mouseX - dot.x;
      var distanceY = mouseY - dot.y;
      var distance = Math.sqrt(distanceX * distanceX + distanceY * distanceY);
      var proximity = Math.max(0, 1 - distance / GLOW_RADIUS);
      var alpha = BASE_ALPHA + proximity * 0.35;
      var radius = DOT_RADIUS + proximity * 1.2;

      ctx.beginPath();
      ctx.arc(dot.x, dot.y, radius, 0, Math.PI * 2);
      ctx.fillStyle =
        "rgba(137, 180, 250, " + Math.min(alpha, 0.5) + ")";
      ctx.fill();
    }

    animationFrame = requestAnimationFrame(draw);
  }

  function handleMouseMove(event) {
    var rect = canvas.getBoundingClientRect();
    mouseX = event.clientX - rect.left;
    mouseY = event.clientY - rect.top;
  }

  function handleMouseLeave() {
    mouseX = -1000;
    mouseY = -1000;
  }

  canvas.addEventListener("mousemove", handleMouseMove);
  canvas.addEventListener("mouseleave", handleMouseLeave);
  window.addEventListener("resize", resize);

  resize();
  draw();
}

function initTerminalDemo() {
  var commandElement = document.getElementById("typedCommand");
  var cursorElement = document.getElementById("cursor");
  var outputElement = document.getElementById("terminalOutput");
  if (!commandElement || !outputElement) return;

  var commands = [
    {
      text: "cocxy agents --status",
      output: [
        { class: "dim", text: "Active AI Agents:" },
        { class: "", text: "" },
        {
          class: "accent",
          text: "  Claude Code     " +
            '<span class="success">running</span>' +
            '   <span class="dim">pid 4821  tab:1</span>',
        },
        {
          class: "accent",
          text: "  Codex CLI       " +
            '<span class="warn">waiting</span>' +
            '   <span class="dim">pid 4903  tab:2</span>',
        },
        {
          class: "accent",
          text: "  Aider           " +
            '<span class="success">running</span>' +
            '   <span class="dim">pid 5012  tab:3</span>',
        },
        { class: "", text: "" },
        {
          class: "dim",
          text: '3 agents detected  <span class="success">all healthy</span>',
        },
      ],
    },
    {
      text: "cocxy split --right --browser localhost:3000",
      output: [
        {
          class: "success",
          text: "Split created. Browser panel open on right.",
        },
        {
          class: "dim",
          text: "Monitoring localhost:3000 for changes...",
        },
      ],
    },
    {
      text: "cocxy hooks --list",
      output: [
        { class: "dim", text: "Registered hooks:" },
        { class: "", text: "" },
        {
          class: "accent",
          text: '  on-agent-start   <span class="dim">notify + log</span>',
        },
        {
          class: "accent",
          text: '  on-agent-finish  <span class="dim">sound + summary</span>',
        },
        {
          class: "accent",
          text: '  on-port-open     <span class="dim">auto-split browser</span>',
        },
        { class: "", text: "" },
        { class: "dim", text: "3 hooks active" },
      ],
    },
  ];

  var currentCommand = 0;
  var charIndex = 0;
  var isTyping = false;
  var TYPING_SPEED = 45;
  var COMMAND_PAUSE = 2500;
  var OUTPUT_PAUSE = 800;

  function typeCommand() {
    if (charIndex >= commands[currentCommand].text.length) {
      isTyping = false;
      cursorElement.style.display = "none";
      setTimeout(showOutput, OUTPUT_PAUSE);
      return;
    }
    isTyping = true;
    charIndex++;
    commandElement.textContent = commands[currentCommand].text.slice(
      0,
      charIndex
    );
    setTimeout(typeCommand, TYPING_SPEED + Math.random() * 30);
  }

  function showOutput() {
    var lines = commands[currentCommand].output;
    outputElement.innerHTML = "";

    lines.forEach(function (line, index) {
      setTimeout(function () {
        var lineElement = document.createElement("span");
        lineElement.className = "line";
        if (line.class) {
          lineElement.innerHTML =
            '<span class="' + line.class + '">' + line.text + "</span>";
        } else {
          lineElement.innerHTML = "&nbsp;";
        }
        outputElement.appendChild(lineElement);
      }, index * 60);
    });

    setTimeout(nextCommand, lines.length * 60 + COMMAND_PAUSE);
  }

  function nextCommand() {
    currentCommand = (currentCommand + 1) % commands.length;
    charIndex = 0;
    commandElement.textContent = "";
    outputElement.innerHTML = "";
    cursorElement.style.display = "";
    setTimeout(typeCommand, 400);
  }

  var observer = new IntersectionObserver(
    function (entries) {
      if (entries[0].isIntersecting && !isTyping) {
        observer.disconnect();
        setTimeout(typeCommand, 600);
      }
    },
    { threshold: 0.3 }
  );

  var demoSection = document.querySelector(".terminal-demo");
  if (demoSection) {
    observer.observe(demoSection);
  }
}

function initCopyButtons() {
  document.querySelectorAll(".copy-btn").forEach(function (button) {
    button.addEventListener("click", function () {
      var textToCopy = button.getAttribute("data-copy");
      if (!textToCopy) return;

      navigator.clipboard.writeText(textToCopy).then(function () {
        button.classList.add("copied");
        var originalSVG = button.innerHTML;
        button.innerHTML =
          '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';
        setTimeout(function () {
          button.classList.remove("copied");
          button.innerHTML = originalSVG;
        }, 2000);
      });
    });
  });
}
