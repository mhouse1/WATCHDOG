#!/bin/bash

# SSH vs Console Display Blanking Explanation

echo "=== SSH vs Console Display Blanking ==="
echo ""

# Detect if we're in SSH
if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" || -n "$SSH_CONNECTION" ]]; then
    echo "🔍 DETECTION: You are connected via SSH"
    echo "   SSH Client: ${SSH_CLIENT:-Not set}"
    echo "   SSH TTY: ${SSH_TTY:-Not set}"
    echo "   SSH Connection: ${SSH_CONNECTION:-Not set}"
    echo ""
    
    echo "📱 HOW SSH AFFECTS DISPLAY BLANKING:"
    echo ""
    echo "✅ SSH Session (what you see):"
    echo "   • Runs on a pseudo-terminal (PTY)"
    echo "   • Your terminal stays active"
    echo "   • No display blanking here"
    echo ""
    
    echo "🖥️  Physical MacBook Pro Console:"
    echo "   • setterm affects the LOCAL screen"
    echo "   • Display WILL blank after 3 minutes of no LOCAL activity"
    echo "   • Even while SSH sessions are active"
    echo ""
    
    echo "🧪 TO TEST DISPLAY BLANKING:"
    echo "1. Walk to your MacBook Pro physically"
    echo "2. Look at the actual screen (not SSH)"
    echo "3. If no one touched it for 3+ minutes, it should be blank"
    echo "4. Press any key on the MacBook keyboard to wake it"
    echo ""
    
    echo "⚠️  IMPORTANT:"
    echo "• SSH activity does NOT prevent local screen blanking"
    echo "• The MacBook display blanks independently of SSH"
    echo "• Your SSH session continues running normally"
    
else
    echo "🔍 DETECTION: You are on the local console"
    echo "   • This session WILL be affected by display blanking"
    echo "   • Screen will blank after 3 minutes of inactivity HERE"
fi

echo ""
echo "🎯 SUMMARY FOR YOUR SITUATION:"
echo "• SSH keeps YOUR terminal active"
echo "• MacBook Pro screen blanks independently"
echo "• Walk to the MacBook to see if screen is actually blank"
echo "• This is working as designed!"

# Show current TTY information
echo ""
echo "📊 TERMINAL INFO:"
echo "   Current TTY: $(tty 2>/dev/null || echo 'Unknown')"
echo "   Terminal Type: $TERM"
echo "   Session Type: $(loginctl show-session $(loginctl show-user $(whoami) -p Sessions --value | cut -d' ' -f1) -p Type --value 2>/dev/null || echo 'Unknown')"