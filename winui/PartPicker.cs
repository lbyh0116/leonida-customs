using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace VehicleStudio;

public sealed class PartPicker : ComboBox
{
    protected override void OnPointerWheelChanged(PointerRoutedEventArgs args)
    {
        if (IsDropDownOpen)
            base.OnPointerWheelChanged(args);
        // Leave the event to the surrounding ScrollViewer when collapsed.
    }
}
